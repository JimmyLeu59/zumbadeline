create or replace function public.set_member_activities(
  p_member_id uuid,
  p_activity_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_app_role(array['admin', 'president', 'assistant']) then
    raise exception 'Not authorized to manage member activities'
      using errcode = '42501';
  end if;
  if p_activity_ids is null or cardinality(p_activity_ids) = 0 then
    raise exception 'A member must be assigned to at least one activity'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from unnest(p_activity_ids) as selected_activity(id)
    left join public.activities a on a.id = selected_activity.id
    where a.id is null or not a.is_active
  ) then
    raise exception 'One or more selected activities are unavailable'
      using errcode = '22023';
  end if;
  if not exists (select 1 from public.members where id = p_member_id) then
    raise exception 'Member not found' using errcode = 'P0002';
  end if;

  update public.member_activities
  set ended_at = case
    when enrolled_at < current_date then current_date - 1
    else enrolled_at
  end
  where member_id = p_member_id
    and not (activity_id = any(p_activity_ids))
    and ended_at is null;
  delete from public.member_activities
  where member_id = p_member_id
    and not (activity_id = any(p_activity_ids))
    and enrolled_at >= current_date;

  insert into public.member_activities (member_id, activity_id, ended_at)
  select distinct p_member_id, selected_activity.id, null::date
  from unnest(p_activity_ids) as selected_activity(id)
  on conflict (member_id, activity_id)
  do update set ended_at = null;
end;
$$;

revoke all on function public.set_member_activities(uuid, uuid[])
  from public, anon;
grant execute on function public.set_member_activities(uuid, uuid[])
  to authenticated;

create or replace function public.create_recurring_event(
  p_session jsonb,
  p_repeats_until date,
  p_interval_weeks integer default 1,
  p_time_zone text default 'Europe/Paris',
  p_assignments jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  activity_id uuid;
  event_id uuid;
  first_start timestamptz;
  first_end timestamptz;
  local_start timestamp;
  occurrence_start timestamptz;
  occurrence_end timestamptz;
  occurrence_date date;
  occurrence_id uuid;
  recurrence jsonb;
  week_number integer;
begin
  if p_session is null
    or coalesce(trim(p_session->>'title'), '') = ''
    or coalesce(trim(p_session->>'activity_id'), '') = ''
    or coalesce(trim(p_session->>'starts_at'), '') = '' then
    raise exception 'Invalid recurring event details' using errcode = '22023';
  end if;
  if p_interval_weeks is null
    or p_interval_weeks < 1
    or p_interval_weeks > 4 then
    raise exception 'Recurrence interval must be between 1 and 4 weeks'
      using errcode = '22023';
  end if;
  if p_repeats_until is null or p_time_zone is null
    or not exists (
      select 1 from pg_catalog.pg_timezone_names
      where name = p_time_zone
    ) then
    raise exception 'A valid recurrence end date and time zone are required'
      using errcode = '22023';
  end if;

  activity_id := (p_session->>'activity_id')::uuid;
  first_start := (p_session->>'starts_at')::timestamptz;
  first_end := nullif(p_session->>'ends_at', '')::timestamptz;
  local_start := first_start at time zone p_time_zone;
  if p_repeats_until < local_start::date then
    raise exception 'Recurrence end date must not precede the first session'
      using errcode = '22023';
  end if;
  if first_end is not null and first_end <= first_start then
    raise exception 'Session end must be after its start'
      using errcode = '22023';
  end if;
  if not public.can_access_activity(activity_id) then
    raise exception 'Not authorized to create events for this activity'
      using errcode = '42501';
  end if;
  if p_assignments is null or jsonb_typeof(p_assignments) <> 'array' then
    raise exception 'Assignments must be a JSON array' using errcode = '22023';
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

  recurrence := jsonb_build_object(
    'freq', 'weekly',
    'interval', p_interval_weeks,
    'byweekday', extract(isodow from local_start)::integer
  );
  insert into public.recurring_events (
    activity_id, title, session_type, starts_at, ends_at, time_zone,
    recurrence_rule, repeats_until, location, capacity,
    preparation_notes, created_by
  )
  values (
    activity_id,
    trim(p_session->>'title'),
    coalesce(nullif(p_session->>'session_type', ''), 'class'),
    first_start,
    first_end,
    p_time_zone,
    recurrence,
    p_repeats_until,
    nullif(trim(p_session->>'location'), ''),
    nullif(p_session->>'capacity', '')::integer,
    nullif(trim(p_session->>'preparation_notes'), ''),
    (select auth.uid())
  )
  returning id into event_id;

  for week_number in 0..(
    (p_repeats_until - local_start::date) / (7 * p_interval_weeks)
  ) loop
    occurrence_date :=
      local_start::date + week_number * 7 * p_interval_weeks;
    occurrence_start :=
      (occurrence_date + local_start::time) at time zone p_time_zone;
    occurrence_end := case
      when first_end is null then null
      else occurrence_start + (first_end - first_start)
    end;
    insert into public.sessions (
      title, session_type, starts_at, ends_at, location, capacity,
      preparation_notes, equipment_checklist, recurrence_rule, status,
      activity_id, recurring_event_id, occurrence_key, created_by
    )
    values (
      trim(p_session->>'title'),
      coalesce(nullif(p_session->>'session_type', ''), 'class'),
      occurrence_start,
      occurrence_end,
      nullif(trim(p_session->>'location'), ''),
      nullif(p_session->>'capacity', '')::integer,
      nullif(trim(p_session->>'preparation_notes'), ''),
      coalesce(p_session->'equipment_checklist', '[]'::jsonb),
      recurrence,
      coalesce(nullif(p_session->>'status', ''), 'scheduled'),
      activity_id,
      event_id,
      occurrence_start,
      (select auth.uid())
    )
    returning id into occurrence_id;

    insert into public.session_instructors (session_id, profile_id, role)
    select
      occurrence_id,
      (item->>'profile_id')::uuid,
      trim(item->>'role')
    from jsonb_array_elements(p_assignments) as entries(item);
  end loop;

  return event_id;
end;
$$;

revoke all on function public.create_recurring_event(
  jsonb, date, integer, text, jsonb
) from public, anon;
grant execute on function public.create_recurring_event(
  jsonb, date, integer, text, jsonb
) to authenticated;

create or replace function public.delete_recurring_occurrence(
  p_session_id uuid,
  p_delete_series boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  series_id uuid;
  session_activity_id uuid;
begin
  select recurring_event_id, activity_id
  into series_id, session_activity_id
  from public.sessions
  where id = p_session_id;
  if not found or series_id is null then
    raise exception 'Recurring occurrence not found' using errcode = 'P0002';
  end if;
  if not public.can_access_activity(session_activity_id) then
    raise exception 'Not authorized to modify this recurring event'
      using errcode = '42501';
  end if;

  if p_delete_series then
    update public.recurring_events
    set is_active = false, updated_at = now()
    where id = series_id;
    delete from public.sessions
    where recurring_event_id = series_id
      and starts_at >= now();
  else
    delete from public.sessions where id = p_session_id;
  end if;
end;
$$;

revoke all on function public.delete_recurring_occurrence(uuid, boolean)
  from public, anon;
grant execute on function public.delete_recurring_occurrence(uuid, boolean)
  to authenticated;

create or replace function public.delete_event(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_activity_id uuid;
begin
  select activity_id into event_activity_id
  from public.sessions
  where id = p_event_id;
  if not found then
    raise exception 'Event not found' using errcode = 'P0002';
  end if;
  if not public.can_access_activity(event_activity_id) then
    raise exception 'Not authorized to delete this event'
      using errcode = '42501';
  end if;

  delete from public.sessions where id = p_event_id;
end;
$$;

revoke all on function public.delete_event(uuid) from public, anon;
grant execute on function public.delete_event(uuid) to authenticated;
