begin;

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typname = 'song_member_role'
  ) then
    create type public.song_member_role as enum ('owner', 'editor', 'listener');
  end if;
end
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null unique,
  display_name text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    lower(coalesce(new.email, new.raw_user_meta_data ->> 'email', new.id::text || '@unknown.local')),
    coalesce(new.raw_user_meta_data ->> 'name', '')
  )
  on conflict (id) do update
    set email = excluded.email,
        display_name = case
          when excluded.display_name = '' then public.profiles.display_name
          else excluded.display_name
        end,
        updated_at = timezone('utc', now());

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

insert into public.profiles (id, email, display_name)
select
  u.id,
  lower(coalesce(u.email, u.id::text || '@unknown.local')),
  coalesce(u.raw_user_meta_data ->> 'name', '')
from auth.users u
on conflict (id) do update
  set email = excluded.email,
      display_name = case
        when excluded.display_name = '' then public.profiles.display_name
        else excluded.display_name
      end,
      updated_at = timezone('utc', now());

create table if not exists public.songs (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  created_by uuid not null references public.profiles (id),
  max_tracks int not null default 16 check (max_tracks = 16),
  current_mix_version_id uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.song_members (
  song_id uuid not null references public.songs (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role public.song_member_role not null,
  added_by uuid references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  primary key (song_id, user_id)
);

create table if not exists public.track_slots (
  id uuid primary key default gen_random_uuid(),
  song_id uuid not null references public.songs (id) on delete cascade,
  slot_index int not null check (slot_index between 1 and 16),
  label text not null,
  assigned_user_id uuid references public.profiles (id),
  current_take_id uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (song_id, slot_index)
);

create table if not exists public.mix_versions (
  id uuid primary key default gen_random_uuid(),
  song_id uuid not null references public.songs (id) on delete cascade,
  file_path text not null,
  format text not null default 'wav',
  sample_rate int not null default 48000,
  bit_depth int not null default 16,
  rendered_by_take_id uuid,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.takes (
  id uuid primary key default gen_random_uuid(),
  song_id uuid not null references public.songs (id) on delete cascade,
  track_slot_id uuid not null references public.track_slots (id) on delete cascade,
  uploaded_by uuid not null references public.profiles (id),
  based_on_mix_version_id uuid references public.mix_versions (id),
  file_path text not null,
  duration_ms int,
  sample_rate int,
  channels int,
  is_selected boolean not null default true,
  created_at timestamptz not null default timezone('utc', now())
);

alter table public.track_slots
  add constraint track_slots_current_take_fk
  foreign key (current_take_id)
  references public.takes (id)
  on delete set null;

alter table public.songs
  add constraint songs_current_mix_version_fk
  foreign key (current_mix_version_id)
  references public.mix_versions (id)
  on delete set null;

create table if not exists public.render_jobs (
  id uuid primary key default gen_random_uuid(),
  song_id uuid not null references public.songs (id) on delete cascade,
  requested_by uuid not null references public.profiles (id),
  status text not null default 'pending' check (status in ('pending', 'processing', 'completed', 'failed')),
  attempts int not null default 0,
  locked_by text,
  locked_at timestamptz,
  payload jsonb not null default '{}'::jsonb,
  error_text text,
  completed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.export_jobs (
  id uuid primary key default gen_random_uuid(),
  song_id uuid not null references public.songs (id) on delete cascade,
  requested_by uuid not null references public.profiles (id),
  output_format text not null check (output_format in ('mp3', 'wav')),
  status text not null default 'pending' check (status in ('pending', 'processing', 'completed', 'failed')),
  attempts int not null default 0,
  locked_by text,
  locked_at timestamptz,
  output_file_path text,
  error_text text,
  completed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists songs_created_by_idx on public.songs (created_by);
create index if not exists song_members_user_idx on public.song_members (user_id);
create index if not exists track_slots_song_idx on public.track_slots (song_id, slot_index);
create index if not exists takes_song_created_idx on public.takes (song_id, created_at desc);
create index if not exists takes_slot_created_idx on public.takes (track_slot_id, created_at desc);
create index if not exists mix_versions_song_created_idx on public.mix_versions (song_id, created_at desc);
create index if not exists render_jobs_status_created_idx on public.render_jobs (status, created_at);
create index if not exists export_jobs_status_created_idx on public.export_jobs (status, created_at);

drop trigger if exists songs_set_updated_at on public.songs;
create trigger songs_set_updated_at
before update on public.songs
for each row
execute function public.set_updated_at();

drop trigger if exists track_slots_set_updated_at on public.track_slots;
create trigger track_slots_set_updated_at
before update on public.track_slots
for each row
execute function public.set_updated_at();

drop trigger if exists render_jobs_set_updated_at on public.render_jobs;
create trigger render_jobs_set_updated_at
before update on public.render_jobs
for each row
execute function public.set_updated_at();

drop trigger if exists export_jobs_set_updated_at on public.export_jobs;
create trigger export_jobs_set_updated_at
before update on public.export_jobs
for each row
execute function public.set_updated_at();

create or replace function public.is_song_member(p_song_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.song_members sm
    where sm.song_id = p_song_id
      and sm.user_id = auth.uid()
  );
$$;

create or replace function public.song_role(p_song_id uuid)
returns public.song_member_role
language sql
stable
security definer
set search_path = public
as $$
  select sm.role
  from public.song_members sm
  where sm.song_id = p_song_id
    and sm.user_id = auth.uid();
$$;

create or replace function public.song_id_from_storage_path(path text)
returns uuid
language plpgsql
immutable
as $$
declare
  first_segment text;
begin
  first_segment := split_part(path, '/', 1);
  if first_segment = '' then
    return null;
  end if;

  return first_segment::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

create or replace function public.create_song_owner_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.song_members (song_id, user_id, role, added_by)
  values (new.id, new.created_by, 'owner', new.created_by)
  on conflict (song_id, user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists songs_create_owner_membership on public.songs;
create trigger songs_create_owner_membership
after insert on public.songs
for each row
execute function public.create_song_owner_membership();

create or replace function public.create_default_track_slots()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.track_slots (song_id, slot_index, label)
  select
    new.id,
    gs.slot_index,
    'Track ' || gs.slot_index::text
  from generate_series(1, 16) as gs(slot_index)
  on conflict (song_id, slot_index) do nothing;

  return new;
end;
$$;

drop trigger if exists songs_create_track_slots on public.songs;
create trigger songs_create_track_slots
after insert on public.songs
for each row
execute function public.create_default_track_slots();

create or replace function public.add_song_member_by_email(
  p_song_id uuid,
  p_member_email text,
  p_role public.song_member_role default 'editor'
)
returns public.song_members
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid;
  target_user_id uuid;
  membership public.song_members;
begin
  caller_id := auth.uid();
  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.song_members sm
    where sm.song_id = p_song_id
      and sm.user_id = caller_id
      and sm.role = 'owner'
  ) then
    raise exception 'Only owners can add song members';
  end if;

  select p.id
  into target_user_id
  from public.profiles p
  where lower(p.email) = lower(trim(p_member_email))
  limit 1;

  if target_user_id is null then
    raise exception 'No user found for email %', p_member_email;
  end if;

  insert into public.song_members (song_id, user_id, role, added_by)
  values (p_song_id, target_user_id, p_role, caller_id)
  on conflict (song_id, user_id) do update
    set role = excluded.role,
        added_by = excluded.added_by
  returning * into membership;

  return membership;
end;
$$;

create or replace function public.remove_song_member(
  p_song_id uuid,
  p_member_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid;
begin
  caller_id := auth.uid();
  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.song_members sm
    where sm.song_id = p_song_id
      and sm.user_id = caller_id
      and sm.role = 'owner'
  ) then
    raise exception 'Only owners can remove song members';
  end if;

  delete from public.song_members
  where song_id = p_song_id
    and user_id = p_member_user_id
    and role <> 'owner';
end;
$$;

grant execute on function public.is_song_member(uuid) to authenticated;
grant execute on function public.song_role(uuid) to authenticated;
grant execute on function public.add_song_member_by_email(uuid, text, public.song_member_role) to authenticated;
grant execute on function public.remove_song_member(uuid, uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.songs enable row level security;
alter table public.song_members enable row level security;
alter table public.track_slots enable row level security;
alter table public.takes enable row level security;
alter table public.mix_versions enable row level security;
alter table public.render_jobs enable row level security;
alter table public.export_jobs enable row level security;

drop policy if exists "profiles_read_own" on public.profiles;
create policy "profiles_read_own"
on public.profiles
for select
to authenticated
using (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

drop policy if exists "songs_select_member" on public.songs;
create policy "songs_select_member"
on public.songs
for select
to authenticated
using (public.is_song_member(id));

drop policy if exists "songs_insert_owner" on public.songs;
create policy "songs_insert_owner"
on public.songs
for insert
to authenticated
with check (created_by = auth.uid());

drop policy if exists "songs_update_owner_editor" on public.songs;
create policy "songs_update_owner_editor"
on public.songs
for update
to authenticated
using (public.song_role(id) in ('owner', 'editor'))
with check (public.song_role(id) in ('owner', 'editor'));

drop policy if exists "songs_delete_owner" on public.songs;
create policy "songs_delete_owner"
on public.songs
for delete
to authenticated
using (public.song_role(id) = 'owner');

drop policy if exists "song_members_select_members" on public.song_members;
create policy "song_members_select_members"
on public.song_members
for select
to authenticated
using (public.is_song_member(song_id));

drop policy if exists "song_members_owner_manage" on public.song_members;
create policy "song_members_owner_manage"
on public.song_members
for all
to authenticated
using (public.song_role(song_id) = 'owner')
with check (public.song_role(song_id) = 'owner');

drop policy if exists "track_slots_select_member" on public.track_slots;
create policy "track_slots_select_member"
on public.track_slots
for select
to authenticated
using (public.is_song_member(song_id));

drop policy if exists "track_slots_owner_editor_manage" on public.track_slots;
create policy "track_slots_owner_editor_manage"
on public.track_slots
for all
to authenticated
using (public.song_role(song_id) in ('owner', 'editor'))
with check (public.song_role(song_id) in ('owner', 'editor'));

drop policy if exists "takes_select_member" on public.takes;
create policy "takes_select_member"
on public.takes
for select
to authenticated
using (public.is_song_member(song_id));

drop policy if exists "takes_insert_owner_editor" on public.takes;
create policy "takes_insert_owner_editor"
on public.takes
for insert
to authenticated
with check (
  uploaded_by = auth.uid()
  and public.song_role(song_id) in ('owner', 'editor')
);

drop policy if exists "takes_update_owner_editor" on public.takes;
create policy "takes_update_owner_editor"
on public.takes
for update
to authenticated
using (public.song_role(song_id) in ('owner', 'editor'))
with check (public.song_role(song_id) in ('owner', 'editor'));

drop policy if exists "mix_versions_select_member" on public.mix_versions;
create policy "mix_versions_select_member"
on public.mix_versions
for select
to authenticated
using (public.is_song_member(song_id));

drop policy if exists "render_jobs_select_member" on public.render_jobs;
create policy "render_jobs_select_member"
on public.render_jobs
for select
to authenticated
using (public.is_song_member(song_id));

drop policy if exists "render_jobs_insert_owner_editor" on public.render_jobs;
create policy "render_jobs_insert_owner_editor"
on public.render_jobs
for insert
to authenticated
with check (
  requested_by = auth.uid()
  and public.song_role(song_id) in ('owner', 'editor')
);

drop policy if exists "export_jobs_select_member" on public.export_jobs;
create policy "export_jobs_select_member"
on public.export_jobs
for select
to authenticated
using (public.is_song_member(song_id));

drop policy if exists "export_jobs_insert_owner_editor" on public.export_jobs;
create policy "export_jobs_insert_owner_editor"
on public.export_jobs
for insert
to authenticated
with check (
  requested_by = auth.uid()
  and public.song_role(song_id) in ('owner', 'editor')
);

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) values
  (
    'takes',
    'takes',
    false,
    524288000,
    array['audio/wav', 'audio/x-wav', 'audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/flac', 'audio/ogg']
  ),
  (
    'mixes',
    'mixes',
    false,
    524288000,
    array['audio/wav', 'audio/x-wav', 'audio/flac', 'audio/mpeg']
  ),
  (
    'exports',
    'exports',
    false,
    1048576000,
    array['audio/wav', 'audio/x-wav', 'audio/flac', 'audio/mpeg', 'application/zip']
  )
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "storage_read_song_objects" on storage.objects;
create policy "storage_read_song_objects"
on storage.objects
for select
to authenticated
using (
  bucket_id in ('takes', 'mixes', 'exports')
  and public.is_song_member(public.song_id_from_storage_path(name))
);

drop policy if exists "storage_insert_takes_objects" on storage.objects;
create policy "storage_insert_takes_objects"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'takes'
  and public.song_role(public.song_id_from_storage_path(name)) in ('owner', 'editor')
);

drop policy if exists "storage_update_takes_objects" on storage.objects;
create policy "storage_update_takes_objects"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'takes'
  and public.song_role(public.song_id_from_storage_path(name)) in ('owner', 'editor')
)
with check (
  bucket_id = 'takes'
  and public.song_role(public.song_id_from_storage_path(name)) in ('owner', 'editor')
);

drop policy if exists "storage_delete_takes_objects" on storage.objects;
create policy "storage_delete_takes_objects"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'takes'
  and public.song_role(public.song_id_from_storage_path(name)) in ('owner', 'editor')
);

commit;
