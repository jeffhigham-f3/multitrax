begin;

alter table public.takes
  add column if not exists submission_id uuid;

create unique index if not exists takes_submission_id_uidx
  on public.takes (submission_id)
  where submission_id is not null;

alter table public.render_jobs
  add column if not exists submission_id uuid;

create unique index if not exists render_jobs_submission_id_uidx
  on public.render_jobs (submission_id)
  where submission_id is not null;

create or replace function public.assert_take_song_slot_consistency()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  slot_song_id uuid;
begin
  select ts.song_id
  into slot_song_id
  from public.track_slots ts
  where ts.id = new.track_slot_id;

  if slot_song_id is null then
    raise exception 'Track slot % not found', new.track_slot_id;
  end if;

  if new.song_id <> slot_song_id then
    raise exception 'Take song_id % must match track slot song_id %', new.song_id, slot_song_id;
  end if;

  return new;
end;
$$;

drop trigger if exists takes_assert_song_slot_consistency on public.takes;
create trigger takes_assert_song_slot_consistency
before insert or update on public.takes
for each row
execute function public.assert_take_song_slot_consistency();

create or replace function public.assert_track_slot_current_take_consistency()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  take_song_id uuid;
  take_slot_id uuid;
begin
  if new.current_take_id is null then
    return new;
  end if;

  select t.song_id, t.track_slot_id
  into take_song_id, take_slot_id
  from public.takes t
  where t.id = new.current_take_id;

  if take_song_id is null then
    raise exception 'Current take % not found', new.current_take_id;
  end if;

  if take_song_id <> new.song_id then
    raise exception 'Current take song_id % must match track slot song_id %', take_song_id, new.song_id;
  end if;

  if take_slot_id <> new.id then
    raise exception 'Current take slot_id % must match track slot id %', take_slot_id, new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists track_slots_assert_current_take_consistency on public.track_slots;
create trigger track_slots_assert_current_take_consistency
before insert or update on public.track_slots
for each row
execute function public.assert_track_slot_current_take_consistency();

create or replace function public.submit_take_and_enqueue_render(
  p_song_id uuid,
  p_track_slot_id uuid,
  p_file_path text,
  p_based_on_mix_version_id uuid default null,
  p_submission_id uuid default null,
  p_duration_ms int default null,
  p_sample_rate int default null,
  p_channels int default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid;
  slot_song_id uuid;
  take_id uuid;
  effective_submission_id uuid;
begin
  caller_id := auth.uid();
  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  if public.song_role(p_song_id) not in ('owner', 'editor') then
    raise exception 'Only owners/editors can submit takes';
  end if;

  select ts.song_id
  into slot_song_id
  from public.track_slots ts
  where ts.id = p_track_slot_id;

  if slot_song_id is null then
    raise exception 'Track slot not found';
  end if;

  if slot_song_id <> p_song_id then
    raise exception 'Track slot does not belong to song';
  end if;

  effective_submission_id := coalesce(p_submission_id, gen_random_uuid());

  insert into public.takes (
    song_id,
    track_slot_id,
    uploaded_by,
    based_on_mix_version_id,
    file_path,
    duration_ms,
    sample_rate,
    channels,
    is_selected,
    submission_id
  )
  values (
    p_song_id,
    p_track_slot_id,
    caller_id,
    p_based_on_mix_version_id,
    p_file_path,
    p_duration_ms,
    p_sample_rate,
    p_channels,
    true,
    effective_submission_id
  )
  on conflict (submission_id) do update
    set file_path = excluded.file_path,
        based_on_mix_version_id = excluded.based_on_mix_version_id,
        duration_ms = excluded.duration_ms,
        sample_rate = excluded.sample_rate,
        channels = excluded.channels
  returning id into take_id;

  update public.track_slots
  set current_take_id = take_id
  where id = p_track_slot_id;

  insert into public.render_jobs (
    song_id,
    requested_by,
    status,
    payload,
    submission_id
  )
  values (
    p_song_id,
    caller_id,
    'pending',
    '{}'::jsonb,
    effective_submission_id
  )
  on conflict (submission_id) do nothing;

  return take_id;
end;
$$;

grant execute on function public.submit_take_and_enqueue_render(
  uuid,
  uuid,
  text,
  uuid,
  uuid,
  int,
  int,
  int
) to authenticated;

commit;
