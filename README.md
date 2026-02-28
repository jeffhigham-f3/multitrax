# Multitrax

Async multitrack recording MVP built with Flutter, self-hosted Supabase, and an FFmpeg worker service.

- **Repository:** https://github.com/jeffhigham-f3/multitrax
- **Author:** Jeff Higham
- **License:** MIT

## What This Project Includes

- Flutter client for iOS, Android, and macOS desktop.
- Self-hosted Supabase for auth, database, storage, and RPCs.
- Dockerized Python worker that mixes tracks and generates exports.
- Async collaboration flow: sync latest state, record/redo, submit, render, export.

## Monorepo Layout

- `apps/multitrax_app` Flutter app
- `supabase` Local Supabase config and SQL migrations
- `services/audio_worker` Worker that processes render/export jobs
- `scripts` Local helper scripts and migration smoke test
- `docs` Architecture and implementation notes

## Prerequisites

- Flutter SDK (stable)
- Dart SDK (bundled with Flutter)
- Node.js 18+ (for `npx supabase`)
- Docker Desktop (for Supabase local stack + audio worker image)
- Python 3.11+ (for worker tests)
- Xcode (for iOS/macOS targets on macOS)

## Quick Start (End-to-End)

### 1) Start local Supabase

```bash
npx supabase start
```

### 2) Run migration smoke checks

```bash
./scripts/test_supabase_migration.sh
```

### 3) Run the Flutter app

```bash
cd apps/multitrax_app
flutter pub get

# Development flavor (recommended local workflow)
flutter run --flavor development -t lib/main_development.dart \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<supabase-anon-key>
```

Optional targets:

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

### 4) Start the audio worker

From repo root:

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

## VS Code Launch Configurations

Preconfigured in `.vscode/launch.json`:

- `Multitrax iOS (development)`
- `Multitrax (development)`
- `Multitrax (staging)`
- `Multitrax (production)`

## Verify Your Setup

```bash
# Flutter quality checks
cd apps/multitrax_app
flutter analyze
flutter test

# Worker smoke test
cd ../..
python3 -m unittest services/audio_worker/tests/test_ffmpeg_pipeline.py
```

## MVP Notes

- Collaboration is async-only.
- Songs use 16 fixed track slots.
- Take submission is idempotent and uses atomic RPC + render enqueue.
- Waveform + scrub is enabled for submitted takes.
- Play-all sync is near-simultaneous (not sample-accurate DAW timing).

## License

This project is licensed under the MIT License.
