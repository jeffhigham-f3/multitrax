# Audio Worker

This service polls Supabase job tables and performs audio processing with FFmpeg.

## Responsibilities

- Claim `render_jobs` and `export_jobs` with transactional `FOR UPDATE SKIP LOCKED`.
- Reclaim stale `processing` jobs after lock timeout.
- Mark jobs as failed when max attempts is reached.
- Build a guide mix from current selected takes.
- Write mix versions back to Supabase Storage (`mixes` bucket) and database.
- Produce export files (`mp3` 320kbps and `wav` 48kHz PCM) in `exports` bucket.

## Required Environment Variables

- `DATABASE_URL` (example: `postgresql://postgres:postgres@host.docker.internal:54322/postgres`)
- `SUPABASE_URL` (example: `http://host.docker.internal:54321`)
- `SUPABASE_SERVICE_ROLE_KEY` (from `supabase status`)
- `POLL_INTERVAL_SECONDS` (optional, default `3`)
- `RECONNECT_BACKOFF_SECONDS` (optional, default `3`)
- `LOCK_TIMEOUT_SECONDS` (optional, default `120`)
- `MAX_JOB_ATTEMPTS` (optional, default `3`)
- `WORKER_ID` (optional, default hostname)

## Run Locally

```bash
docker build -t multitrax-audio-worker services/audio_worker
docker run --rm \
  --name multitrax-audio-worker \
  -e DATABASE_URL="postgresql://postgres:postgres@host.docker.internal:54322/postgres" \
  -e SUPABASE_URL="http://host.docker.internal:54321" \
  -e SUPABASE_SERVICE_ROLE_KEY="<your-local-service-role-key>" \
  -e POLL_INTERVAL_SECONDS=3 \
  -e RECONNECT_BACKOFF_SECONDS=3 \
  -e LOCK_TIMEOUT_SECONDS=120 \
  -e MAX_JOB_ATTEMPTS=3 \
  multitrax-audio-worker
```

When running outside Docker, install dependencies from `requirements.txt` and execute:

```bash
python services/audio_worker/worker.py
```
