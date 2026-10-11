create table public.card_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  card_id uuid not null references public.cards (id) on delete cascade,
  kind text not null check (kind in ('expiry', 'last_class')),
  member_name text not null,
  activity_name text not null,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  unique (recipient_id, card_id, kind)
);

alter table public.card_notifications enable row level security;
create policy "Staff can read their card notifications"
  on public.card_notifications for select to authenticated
  using (recipient_id = (select auth.uid()));
create policy "Staff can update their card notifications"
  on public.card_notifications for update to authenticated
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));

grant select on public.card_notifications to authenticated;
grant update (read_at) on public.card_notifications to authenticated;

create or replace function public.generate_card_notifications()
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.card_notifications (
    recipient_id, card_id, kind, member_name, activity_name, expires_at
  )
  select
    p.id,
    c.id,
    reminder.kind,
    m.first_name || ' ' || m.last_name,
    coalesce(a.name, 'vos cours'),
    c.expires_at
  from public.cards c
  join public.members m on m.id = c.member_id
  join public.activities a on a.id = c.activity_id
  cross join lateral (
    select 'expiry'::text as kind
    where c.expires_at is not null
      and c.remaining_passes > 0
      and c.expires_at >= now()
      and c.expires_at <= now() + interval '7 days'
    union all
    select 'last_class'
    where c.remaining_passes = 1
      and (c.expires_at is null or c.expires_at >= now())
  ) reminder
  join public.profiles p
    on p.role in ('admin', 'president', 'treasurer', 'assistant', 'instructor')
  where m.is_active
  on conflict (recipient_id, card_id, kind) do nothing;
$$;

revoke all on function public.generate_card_notifications()
  from public, anon, authenticated;

create extension if not exists pg_cron with schema pg_catalog;

do $$
declare
  existing_job_id bigint;
begin
  select jobid into existing_job_id
  from cron.job
  where jobname = 'generate-card-notifications';
  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;

  perform cron.schedule(
    'generate-card-notifications',
    '0 9 * * *',
    'select public.generate_card_notifications();'
  );
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'card_notifications'
  ) then
    alter publication supabase_realtime
      add table public.card_notifications;
  end if;
end;
$$;

select public.generate_card_notifications();
