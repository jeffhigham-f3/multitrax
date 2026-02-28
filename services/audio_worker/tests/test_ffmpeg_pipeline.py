import subprocess
import tempfile
import unittest
from pathlib import Path


class FfmpegPipelineTest(unittest.TestCase):
    def test_mix_two_generated_stems(self) -> None:
        with tempfile.TemporaryDirectory(prefix="audio-worker-test-") as temp_dir:
            temp_path = Path(temp_dir)
            stem_a = temp_path / "stem_a.wav"
            stem_b = temp_path / "stem_b.wav"
            mixed = temp_path / "mixed.wav"

            self._run(
                [
                    "ffmpeg",
                    "-y",
                    "-f",
                    "lavfi",
                    "-i",
                    "sine=frequency=440:duration=1",
                    "-ar",
                    "48000",
                    str(stem_a),
                ]
            )
            self._run(
                [
                    "ffmpeg",
                    "-y",
                    "-f",
                    "lavfi",
                    "-i",
                    "sine=frequency=660:duration=1",
                    "-ar",
                    "48000",
                    str(stem_b),
                ]
            )
            self._run(
                [
                    "ffmpeg",
                    "-y",
                    "-i",
                    str(stem_a),
                    "-i",
                    str(stem_b),
                    "-filter_complex",
                    "amix=inputs=2:normalize=0,alimiter=limit=0.95",
                    "-ar",
                    "48000",
                    "-ac",
                    "2",
                    str(mixed),
                ]
            )

            self.assertTrue(mixed.exists())
            self.assertGreater(mixed.stat().st_size, 0)

    def _run(self, command: list[str]) -> None:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(
                f"Command failed ({completed.returncode}): {' '.join(command)}\n"
                f"stderr:\n{completed.stderr}"
            )


if __name__ == "__main__":
    unittest.main()
