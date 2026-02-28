#!/usr/bin/env bash
set -euo pipefail

DB_CONTAINER="${SUPABASE_DB_CONTAINER:-supabase_db_multitrax}"

if ! docker ps --format '{{.Names}}' | grep -Fxq "${DB_CONTAINER}"; then
  echo "Supabase DB container '${DB_CONTAINER}' is not running."
  echo "Start it first with: npx supabase start"
  exit 1
fi

query() {
  local sql="$1"
  docker exec "${DB_CONTAINER}" psql -U postgres -d postgres -Atc "${sql}"
}

echo "Checking required tables..."
for table in songs song_members track_slots takes mix_versions render_jobs export_jobs profiles; do
  exists="$(query "select exists(select 1 from information_schema.tables where table_schema='public' and table_name='${table}');")"
  if [[ "${exists}" != "t" ]]; then
    echo "Missing table: ${table}"
    exit 1
  fi
done

echo "Checking RLS enabled..."
for table in songs song_members track_slots takes mix_versions render_jobs export_jobs profiles; do
  rls="$(query "select relrowsecurity from pg_class where oid = 'public.${table}'::regclass;")"
  if [[ "${rls}" != "t" ]]; then
    echo "RLS disabled for table: ${table}"
    exit 1
  fi
done

echo "Checking required storage buckets..."
for bucket in takes mixes exports; do
  exists="$(query "select exists(select 1 from storage.buckets where id='${bucket}');")"
  if [[ "${exists}" != "t" ]]; then
    echo "Missing bucket: ${bucket}"
    exit 1
  fi
done

echo "Checking required RPC functions..."
for rpc_name in add_song_member_by_email submit_take_and_enqueue_render; do
  rpc_exists="$(query "select exists(select 1 from pg_proc where proname='${rpc_name}');")"
  if [[ "${rpc_exists}" != "t" ]]; then
    echo "Missing RPC: ${rpc_name}"
    exit 1
  fi
done

echo "Checking integrity triggers..."
for trigger_name in takes_assert_song_slot_consistency track_slots_assert_current_take_consistency; do
  trigger_exists="$(query "select exists(select 1 from pg_trigger where tgname='${trigger_name}' and not tgisinternal);")"
  if [[ "${trigger_exists}" != "t" ]]; then
    echo "Missing trigger: ${trigger_name}"
    exit 1
  fi
done

echo "Supabase migration smoke test passed."
