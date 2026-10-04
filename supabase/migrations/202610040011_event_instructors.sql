create table if not exists public.session_instructors (
  session_id uuid not null references public.sessions (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete restrict,
  role text not null check (length(trim(role)) > 0),
  created_at timestamptz not null default now(),
  primary key (session_id, profile_id)
);

alter table public.session_instructors enable row level security;
grant select on public.session_instructors to authenticated;

drop policy if exists "Staff can read event instructors"
  on public.session_instructors;
create policy "Staff can read event instructors"
  on public.session_instructors for select to authenticated
  using (public.has_app_role(array['admin', 'assistant']));

create or replace function public.save_event_with_instructors(
  p_session jsonb,
  p_assignments jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  saved_event public.sessions;
begin
  if not public.has_app_role(array['admin', 'assistant']) then
    raise exception 'Not authorized to assign event instructors'
      using errcode = '42501';
  end if;
  if p_session is null
    or jsonb_typeof(p_session) <> 'object'
    or p_session->>'session_type' <> 'event'
    or coalesce(trim(p_session->>'title'), '') = ''
    or coalesce(trim(p_session->>'starts_at'), '') = '' then
    raise exception 'Invalid event details' using errcode = '22023';
  end if;
  if p_assignments is null or jsonb_typeof(p_assignments) <> 'array' then
    raise exception 'Assignments must be a JSON array'
      using errcode = '22023';
  end if;
  if exists (
    select item->>'profile_id'
    from jsonb_array_elements(p_assignments) as entries(item)
    group by item->>'profile_id'
    having count(*) > 1
  ) then
    raise exception 'An instructor can only be assigned once per event'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_assignments) as entries(item)
    where coalesce(trim(item->>'role'), '') = ''
      or coalesce(trim(item->>'profile_id'), '') = ''
  ) then
    raise exception 'Every assignment needs an instructor and role'
      using errcode = '22023';
  end if;

  insert into public.sessions (
    id,
    title,
    session_type,
    starts_at,
    ends_at,
    location,
    capacity,
    preparation_notes,
    equipment_checklist,
    status
  )
  values (
    coalesce(nullif(p_session->>'id', '')::uuid, gen_random_uuid()),
    trim(p_session->>'title'),
    'event',
    (p_session->>'starts_at')::timestamptz,
    nullif(p_session->>'ends_at', '')::timestamptz,
    nullif(trim(p_session->>'location'), ''),
    nullif(p_session->>'capacity', '')::integer,
    nullif(trim(p_session->>'preparation_notes'), ''),
    coalesce(p_session->'equipment_checklist', '[]'::jsonb),
    coalesce(nullif(p_session->>'status', ''), 'scheduled')
  )
  on conflict (id) do update set
    title = excluded.title,
    starts_at = excluded.starts_at,
    ends_at = excluded.ends_at,
    location = excluded.location,
    capacity = excluded.capacity,
    preparation_notes = excluded.preparation_notes,
    equipment_checklist = excluded.equipment_checklist,
    status = excluded.status,
    updated_at = now()
  returning * into saved_event;

  delete from public.session_instructors
  where session_id = saved_event.id;

  insert into public.session_instructors (session_id, profile_id, role)
  select
    saved_event.id,
    (item->>'profile_id')::uuid,
    trim(item->>'role')
  from jsonb_array_elements(p_assignments) as entries(item);

  return to_jsonb(saved_event);
end;
$$;

revoke all on function public.save_event_with_instructors(jsonb, jsonb)
  from public, anon;
grant execute on function public.save_event_with_instructors(jsonb, jsonb)
  to authenticated;
