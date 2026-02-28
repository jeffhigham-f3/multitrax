begin;

-- Backfill legacy rows created before submission_id was required.
update public.takes
set submission_id = gen_random_uuid()
where submission_id is null;

update public.render_jobs
set submission_id = gen_random_uuid()
where submission_id is null;

-- Defensive dedupe in case any non-null submission IDs were duplicated.
with ranked as (
  select
    id,
    row_number() over (partition by submission_id order by created_at, id) as rn
  from public.takes
  where submission_id is not null
)
update public.takes t
set submission_id = gen_random_uuid()
from ranked r
where t.id = r.id
  and r.rn > 1;

with ranked as (
  select
    id,
    row_number() over (partition by submission_id order by created_at, id) as rn
  from public.render_jobs
  where submission_id is not null
)
update public.render_jobs j
set submission_id = gen_random_uuid()
from ranked r
where j.id = r.id
  and r.rn > 1;

drop index if exists public.takes_submission_id_uidx;
drop index if exists public.render_jobs_submission_id_uidx;

alter table public.takes
  alter column submission_id set not null;

alter table public.render_jobs
  alter column submission_id set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'takes_submission_id_key'
      and conrelid = 'public.takes'::regclass
  ) then
    alter table public.takes
      add constraint takes_submission_id_key unique (submission_id);
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'render_jobs_submission_id_key'
      and conrelid = 'public.render_jobs'::regclass
  ) then
    alter table public.render_jobs
      add constraint render_jobs_submission_id_key unique (submission_id);
  end if;
end;
$$;

commit;
