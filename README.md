<p align="center">
  <img src="img/multitrax.png" alt="Multitrax" />
</p>

# Multitrax

## Async Collaboration Framework

Multitrax is a Flutter + self-hosted Supabase MVP for async multitrack recording and collaboration.

The core loop is intentionally simple:

1. sync latest song state,
2. record or redo locally,
3. submit a take,
4. render a new mix,
5. export when ready.

## What Is The Multitrack Collaboration Loop?

An async song session is a repeated workflow where every submission can trigger a new render, then collaborators sync and continue.

```mermaid
flowchart TD
  syncLatest[SyncLatestState] --> recordTake[RecordTake]
  recordTake --> redoOrSubmit[RedoOrSubmit]
  redoOrSubmit -->|Redo| recordTake
  redoOrSubmit -->|Submit| uploadTake[UploadTake]
  uploadTake --> enqueueRender[EnqueueRenderJob]
  enqueueRender --> workerRender[WorkerRenderMix]
  workerRender --> mixReady[MixReady]
  mixReady --> syncLatest
  mixReady --> optionalExport[OptionalExportMP3orWAV]
```

## Quick Start

1. Start local Supabase:

   ```bash
   npx supabase start
   ```

2. Run migration smoke checks:

   ```bash
   ./scripts/test_supabase_migration.sh
   ```

3. Run the Flutter app (development flavor):

   ```bash
   cd apps/multitrax_app
   flutter pub get
   flutter run --flavor development -t lib/main_development.dart \
     --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
     --dart-define=SUPABASE_ANON_KEY=<supabase-anon-key>
   ```

4. Start the audio worker (from repo root):

   ```bash
   docker build -t multitrax-audio-worker services/audio_worker
   docker run --rm \
     -e DATABASE_URL="postgresql://postgres:postgres@host.docker.internal:54322/postgres" \
     -e SUPABASE_URL="http://host.docker.internal:54321" \
     -e SUPABASE_SERVICE_ROLE_KEY="<supabase-service-role-key>" \
     -e POLL_INTERVAL_SECONDS=3 \
     -e RECONNECT_BACKOFF_SECONDS=3 \
     -e LOCK_TIMEOUT_SECONDS=120 \
     -e MAX_JOB_ATTEMPTS=3 \
     multitrax-audio-worker
   ```

## Core Concepts In This Repo

- `Song`: collaboration unit with 16 fixed track slots.
- `Take`: immutable uploaded audio for one track slot.
- `MixVersion`: rendered guide mix from current selected takes.
- `RenderJob`: worker task to produce a new mix.
- `ExportJob`: worker task to generate MP3/WAV from current mix.
- `SubmissionId`: idempotency key for robust take submission.
- `PlaybackModule`: track playback, waveform, scrub, and play-all behavior.

## High-Level Architecture

```mermaid
flowchart LR
  flutterApp[FlutterApp] --> supabaseApi[SupabaseAuthAndPostgres]
  flutterApp --> supabaseStorage[SupabaseStorage]
  flutterApp --> renderJobs[RenderJobsTable]
  renderJobs --> audioWorker[AudioWorkerFFmpeg]
  audioWorker --> supabaseStorage
  audioWorker --> mixVersions[MixVersionsTable]
  flutterApp --> exportJobs[ExportJobsTable]
  exportJobs --> audioWorker
```

## Architecture Deep Dive

### 1) Entry + Wiring

- Flutter app composition and providers live under `apps/multitrax_app/lib/app`.
- Supabase client, repositories, cache stores, and services are wired at app startup.

### 2) Collaboration Loop Engine

- `SongDetailCubit` owns sync, recording, submit, retry, and export-request transitions.
- Sync + submit operations are network-safe and designed for eventual consistency.

### 3) Data + Backend Layer

- Supabase tables model songs, members, slots, takes, mixes, render jobs, and export jobs.
- RLS policies enforce owner/editor/listener permissions per song.
- RPC `submit_take_and_enqueue_render` keeps submission + render enqueue atomic.

### 4) Worker Layer

- Python worker polls `render_jobs` and `export_jobs`.
- FFmpeg mixes selected takes and generates MP3/WAV exports.
- Worker reclaims stale jobs and marks exhausted retries as failed.

### 5) Playback + UX Layer

- Dedicated playback module in `apps/multitrax_app/lib/playback`.
- Per-track playback, play-all selection, waveform visualization, and scrub controls.
- Session-local play-all track inclusion avoids heavy in-flight player churn.

### 6) Reliability + Validation

- Upload retry/backoff with persistent queue.
- Idempotent submission keys to prevent duplicate writes.
- Test coverage for cubits, repository behavior, navigation, and playback interactions.

## Project Structure

- `apps/multitrax_app` Flutter app (iOS/Android/macOS)
- `supabase` local stack config, migrations, and seed data
- `services/audio_worker` Dockerized FFmpeg worker service
- `scripts` migration smoke test and local helper scripts
- `docs` architecture and implementation notes

## Environment Variables

App runtime:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Worker runtime:

- `DATABASE_URL`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `POLL_INTERVAL_SECONDS`
- `RECONNECT_BACKOFF_SECONDS`
- `LOCK_TIMEOUT_SECONDS`
- `MAX_JOB_ATTEMPTS`

## Scripts And Verification

Flutter checks:

```bash
cd apps/multitrax_app
flutter analyze
flutter test
```

Worker smoke test:

```bash
cd ../..
python3 -m unittest services/audio_worker/tests/test_ffmpeg_pipeline.py
```

Useful Flutter run targets:

```bash
# iOS simulator/device
flutter run --flavor development -t lib/main_development.dart -d ios \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<supabase-anon-key>

# macOS
flutter run --flavor development -t lib/main_development.dart -d macos \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<supabase-anon-key>
```

## Runtime Notes

- Collaboration is async-only for this MVP.
- Exports require a rendered current mix to exist.
- Songs use 16 fixed track slots.
- Play-all timing is near-simultaneous, not sample-accurate DAW sync.

## License + Author + Repository

- **License:** MIT
- **Author:** Jeff Higham
- **Repository:** https://github.com/jeffhigham-f3/multitrax
