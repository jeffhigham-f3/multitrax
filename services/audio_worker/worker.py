import dataclasses
import logging
import os
import socket
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row
from supabase import Client, create_client


logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger("audio-worker")


@dataclasses.dataclass(frozen=True)
class Settings:
    database_url: str
    supabase_url: str
    supabase_service_role_key: str
    poll_interval_seconds: float
    reconnect_backoff_seconds: float
    lock_timeout_seconds: int
    max_attempts: int
    worker_id: str

    @staticmethod
    def from_env() -> "Settings":
        missing = []
        for key in ("DATABASE_URL", "SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"):
            if not os.environ.get(key):
                missing.append(key)
        if missing:
            raise RuntimeError(f"Missing required environment variables: {', '.join(missing)}")

        return Settings(
            database_url=os.environ["DATABASE_URL"],
            supabase_url=os.environ["SUPABASE_URL"],
            supabase_service_role_key=os.environ["SUPABASE_SERVICE_ROLE_KEY"],
            poll_interval_seconds=float(os.environ.get("POLL_INTERVAL_SECONDS", "3")),
            reconnect_backoff_seconds=float(
                os.environ.get("RECONNECT_BACKOFF_SECONDS", "3")
            ),
            lock_timeout_seconds=int(os.environ.get("LOCK_TIMEOUT_SECONDS", "120")),
            max_attempts=int(os.environ.get("MAX_JOB_ATTEMPTS", "3")),
            worker_id=os.environ.get("WORKER_ID", socket.gethostname()),
        )


class AudioWorker:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._supabase: Client = create_client(
            settings.supabase_url, settings.supabase_service_role_key
        )
        self._db = psycopg.connect(
            settings.database_url, row_factory=dict_row, autocommit=False
        )

    def run(self) -> None:
        logger.info("Starting worker id=%s", self._settings.worker_id)
        while True:
            processed_any = False
            try:
                self._fail_exhausted_jobs("render_jobs")
                self._fail_exhausted_jobs("export_jobs")

                render_job = self._claim_job("render_jobs")
                if render_job is not None:
                    processed_any = True
                    self._handle_render_job(render_job)

                export_job = self._claim_job("export_jobs")
                if export_job is not None:
                    processed_any = True
                    self._handle_export_job(export_job)
            except psycopg.Error:
                logger.exception("Database error in worker loop; reconnecting.")
                self._reconnect_db()
                time.sleep(self._settings.reconnect_backoff_seconds)
                continue
            except Exception:  # noqa: BLE001 - keep worker alive in unexpected cases
                logger.exception("Unexpected worker loop failure.")
                time.sleep(self._settings.poll_interval_seconds)
                continue

            if not processed_any:
                time.sleep(self._settings.poll_interval_seconds)

    def _claim_job(self, table_name: str) -> dict[str, Any] | None:
        if table_name not in {"render_jobs", "export_jobs"}:
            raise ValueError("Unsupported table claim request")

        query = f"""
            with next_job as (
              select id
              from public.{table_name}
              where (
                status = 'pending'
                or (
                  status = 'processing'
                  and locked_at is not null
                  and locked_at < timezone('utc', now()) - make_interval(secs => %s)
                )
              )
              and attempts < %s
              order by created_at
              for update skip locked
              limit 1
            )
            update public.{table_name} job
            set
              status = 'processing',
              attempts = job.attempts + 1,
              locked_at = timezone('utc', now()),
              locked_by = %s,
              error_text = null
            from next_job
            where job.id = next_job.id
            returning job.*;
        """

        with self._db.cursor() as cursor:
            cursor.execute(
                query,
                (
                    self._settings.lock_timeout_seconds,
                    self._settings.max_attempts,
                    self._settings.worker_id,
                ),
            )
            claimed = cursor.fetchone()

        self._db.commit()
        return claimed

    def _fail_exhausted_jobs(self, table_name: str) -> None:
        if table_name not in {"render_jobs", "export_jobs"}:
            raise ValueError("Unsupported table update request")

        with self._db.cursor() as cursor:
            cursor.execute(
                f"""
                update public.{table_name}
                set status = 'failed',
                    error_text = coalesce(error_text, 'Maximum attempts exceeded'),
                    updated_at = timezone('utc', now())
                where status in ('pending', 'processing')
                  and attempts >= %s
                """,
                (self._settings.max_attempts,),
            )
        self._db.commit()

    def _reconnect_db(self) -> None:
        try:
            self._db.close()
        except Exception:  # noqa: BLE001
            logger.debug("Ignoring DB close error during reconnect.", exc_info=True)
        self._db = psycopg.connect(
            self._settings.database_url,
            row_factory=dict_row,
            autocommit=False,
        )

    def _handle_render_job(self, job: dict[str, Any]) -> None:
        job_id = job["id"]
        logger.info("Processing render job %s for song %s", job_id, job["song_id"])
        try:
            with tempfile.TemporaryDirectory(prefix=f"render-{job_id}-") as work_dir:
                output_path = self._render_mix(
                    song_id=job["song_id"],
                    work_directory=Path(work_dir),
                    job_id=job_id,
                )
                object_path = f"{job['song_id']}/mix_{job_id}.wav"
                self._upload_file(
                    bucket="mixes",
                    object_path=object_path,
                    local_file_path=output_path,
                    content_type="audio/wav",
                )
                mix_version_id = self._persist_mix_version(
                    song_id=job["song_id"],
                    object_path=object_path,
                )
                logger.info(
                    "Render job %s produced mix version %s",
                    job_id,
                    mix_version_id,
                )
                self._mark_job_completed("render_jobs", job_id)
        except Exception as error:  # noqa: BLE001 - worker should never crash on one job
            logger.exception("Render job %s failed", job_id)
            self._mark_job_failed("render_jobs", job_id, str(error))

    def _handle_export_job(self, job: dict[str, Any]) -> None:
        job_id = job["id"]
        logger.info(
            "Processing export job %s for song %s (%s)",
            job_id,
            job["song_id"],
            job["output_format"],
        )
        try:
            with tempfile.TemporaryDirectory(prefix=f"export-{job_id}-") as work_dir:
                output_path = self._render_export(
                    song_id=job["song_id"],
                    output_format=job["output_format"],
                    work_directory=Path(work_dir),
                    job_id=job_id,
                )
                extension = output_path.suffix.lstrip(".")
                object_path = f"{job['song_id']}/export_{job_id}.{extension}"
                content_type = "audio/mpeg" if extension == "mp3" else "audio/wav"
                self._upload_file(
                    bucket="exports",
                    object_path=object_path,
                    local_file_path=output_path,
                    content_type=content_type,
                )
                self._mark_export_job_completed(job_id=job_id, output_file_path=object_path)
        except Exception as error:  # noqa: BLE001 - worker should never crash on one job
            logger.exception("Export job %s failed", job_id)
            self._mark_job_failed("export_jobs", job_id, str(error))

    def _render_mix(self, song_id: str, work_directory: Path, job_id: str) -> Path:
        takes = self._fetch_selected_takes(song_id)
        if not takes:
            raise RuntimeError("Cannot render mix: no selected takes found.")

        input_files: list[Path] = []
        for index, take in enumerate(takes):
            take_file_path = take["file_path"]
            payload = self._supabase.storage.from_("takes").download(take_file_path)
            extension = Path(take_file_path).suffix or ".wav"
            local_input = work_directory / f"input_{index}{extension}"
            local_input.write_bytes(payload)
            input_files.append(local_input)

        output_file = work_directory / f"mix_{job_id}.wav"
        ffmpeg_inputs: list[str] = []
        for input_file in input_files:
            ffmpeg_inputs.extend(["-i", str(input_file)])

        if len(input_files) == 1:
            ffmpeg_command = [
                "ffmpeg",
                "-y",
                *ffmpeg_inputs,
                "-ar",
                "48000",
                "-ac",
                "2",
                "-af",
                "alimiter=limit=0.95",
                str(output_file),
            ]
        else:
            ffmpeg_command = [
                "ffmpeg",
                "-y",
                *ffmpeg_inputs,
                "-filter_complex",
                f"amix=inputs={len(input_files)}:normalize=0,alimiter=limit=0.95",
                "-ar",
                "48000",
                "-ac",
                "2",
                str(output_file),
            ]

        self._run_ffmpeg(ffmpeg_command)
        return output_file

    def _render_export(
        self,
        song_id: str,
        output_format: str,
        work_directory: Path,
        job_id: str,
    ) -> Path:
        mix_path = self._fetch_current_mix_path(song_id)
        if mix_path is None:
            raise RuntimeError("Cannot export: no current mix exists for song.")

        mix_bytes = self._supabase.storage.from_("mixes").download(mix_path)
        input_file = work_directory / "current_mix.wav"
        input_file.write_bytes(mix_bytes)

        if output_format == "mp3":
            output_file = work_directory / f"export_{job_id}.mp3"
            ffmpeg_command = [
                "ffmpeg",
                "-y",
                "-i",
                str(input_file),
                "-codec:a",
                "libmp3lame",
                "-b:a",
                "320k",
                str(output_file),
            ]
        elif output_format == "wav":
            output_file = work_directory / f"export_{job_id}.wav"
            ffmpeg_command = [
                "ffmpeg",
                "-y",
                "-i",
                str(input_file),
                "-ar",
                "48000",
                "-ac",
                "2",
                "-c:a",
                "pcm_s16le",
                str(output_file),
            ]
        else:
            raise RuntimeError(f"Unsupported export format: {output_format}")

        self._run_ffmpeg(ffmpeg_command)
        return output_file

    def _persist_mix_version(self, song_id: str, object_path: str) -> str:
        with self._db.cursor() as cursor:
            cursor.execute(
                """
                insert into public.mix_versions (song_id, file_path, format, sample_rate, bit_depth)
                values (%s, %s, 'wav', 48000, 16)
                returning id
                """,
                (song_id, object_path),
            )
            mix_version = cursor.fetchone()
            if mix_version is None:
                raise RuntimeError("Failed to persist mix version.")
            mix_version_id = mix_version["id"]
            cursor.execute(
                """
                update public.songs
                set current_mix_version_id = %s,
                    updated_at = timezone('utc', now())
                where id = %s
                """,
                (mix_version_id, song_id),
            )
        self._db.commit()
        return mix_version_id

    def _fetch_selected_takes(self, song_id: str) -> list[dict[str, Any]]:
        with self._db.cursor() as cursor:
            cursor.execute(
                """
                select t.file_path, ts.slot_index
                from public.track_slots ts
                join public.takes t on t.id = ts.current_take_id
                where ts.song_id = %s
                order by ts.slot_index
                """,
                (song_id,),
            )
            return cursor.fetchall()

    def _fetch_current_mix_path(self, song_id: str) -> str | None:
        with self._db.cursor() as cursor:
            cursor.execute(
                """
                select mv.file_path
                from public.songs s
                join public.mix_versions mv on mv.id = s.current_mix_version_id
                where s.id = %s
                """,
                (song_id,),
            )
            row = cursor.fetchone()
            if row is None:
                return None
            return row["file_path"]

    def _upload_file(
        self,
        bucket: str,
        object_path: str,
        local_file_path: Path,
        content_type: str,
    ) -> None:
        file_payload = local_file_path.read_bytes()
        self._supabase.storage.from_(bucket).upload(
            path=object_path,
            file=file_payload,
            file_options={"content-type": content_type, "upsert": "true"},
        )

    def _mark_job_completed(self, table_name: str, job_id: str) -> None:
        with self._db.cursor() as cursor:
            cursor.execute(
                f"""
                update public.{table_name}
                set status = 'completed',
                    completed_at = timezone('utc', now()),
                    updated_at = timezone('utc', now()),
                    error_text = null
                where id = %s
                """,
                (job_id,),
            )
        self._db.commit()

    def _mark_export_job_completed(self, job_id: str, output_file_path: str) -> None:
        with self._db.cursor() as cursor:
            cursor.execute(
                """
                update public.export_jobs
                set status = 'completed',
                    output_file_path = %s,
                    completed_at = timezone('utc', now()),
                    updated_at = timezone('utc', now()),
                    error_text = null
                where id = %s
                """,
                (output_file_path, job_id),
            )
        self._db.commit()

    def _mark_job_failed(self, table_name: str, job_id: str, error_text: str) -> None:
        clean_error = (error_text or "unknown worker error").strip()
        max_error_length = 2000
        clean_error = clean_error[:max_error_length]
        with self._db.cursor() as cursor:
            cursor.execute(
                f"""
                update public.{table_name}
                set status = 'failed',
                    error_text = %s,
                    updated_at = timezone('utc', now())
                where id = %s
                """,
                (clean_error, job_id),
            )
        self._db.commit()

    @staticmethod
    def _run_ffmpeg(command: list[str]) -> None:
        logger.debug("Running ffmpeg command: %s", " ".join(command))
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            logger.error("ffmpeg stderr: %s", completed.stderr)
            raise RuntimeError("ffmpeg command failed")


def main() -> None:
    settings = Settings.from_env()
    worker = AudioWorker(settings)
    worker.run()


if __name__ == "__main__":
    main()
