alter table public.session_tracks
  add column played boolean not null default true;

update public.session_tracks st
set played = s.status = 'completed'
from public.sessions s
where s.id = st.session_id;

create table public.session_closures (
  session_id uuid primary key references public.sessions (id) on delete cascade,
  closed_at timestamptz not null default now(),
  closed_by uuid references public.profiles (id) on delete set null,
  follow_up_notes text
);

create table public.session_absences (
  session_id uuid not null references public.sessions (id) on delete cascade,
  member_id uuid not null references public.members (id) on delete restrict,
  confirmed_at timestamptz not null default now(),
  confirmed_by uuid references public.profiles (id) on delete set null,
  corrected_at timestamptz,
  corrected_by uuid references public.profiles (id) on delete set null,
  primary key (session_id, member_id)
);

create index session_absences_member_idx
  on public.session_absences (member_id, confirmed_at desc);

create table public.repertoire_songs (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities (id) on delete restrict,
  title text not null check (length(trim(title)) > 0),
  composer text not null default '',
  key_signature text not null default '',
  vocal_range text not null default '',
  vocal_part text not null default '',
  accompaniment text not null default '',
  duration_seconds integer not null default 0
    check (duration_seconds >= 0),
  rehearsal_notes text,
  document_path text,
  last_played_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index repertoire_songs_activity_title_idx
  on public.repertoire_songs (activity_id, title);

create or replace function public.is_singing_activity(p_activity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.activities
    where id = p_activity_id and icon in ('mic', 'music_note')
  )
$$;

revoke all on function public.is_singing_activity(uuid) from public, anon;
grant execute on function public.is_singing_activity(uuid) to authenticated;

create table public.session_repertoire_items (
  session_id uuid not null references public.sessions (id) on delete cascade,
  song_id uuid not null references public.repertoire_songs (id) on delete restrict,
  position integer not null check (position >= 0),
  played boolean not null default false,
  primary key (session_id, song_id),
  unique (session_id, position)
);

alter table public.session_closures enable row level security;
alter table public.session_absences enable row level security;
alter table public.repertoire_songs enable row level security;
alter table public.session_repertoire_items enable row level security;

create policy "Staff can read session closures by activity"
  on public.session_closures for select to authenticated
  using (
    exists (
      select 1 from public.sessions s
      where s.id = session_closures.session_id
        and public.can_access_activity(s.activity_id)
    )
  );

create policy "Staff can read session absences by activity"
  on public.session_absences for select to authenticated
  using (
    exists (
      select 1 from public.sessions s
      where s.id = session_absences.session_id
        and public.can_access_activity(s.activity_id)
    )
  );

create policy "Staff can read singing repertoire by activity"
  on public.repertoire_songs for select to authenticated
  using (
    public.can_access_activity(activity_id)
    and public.is_singing_activity(activity_id)
  );
create policy "Staff can manage singing repertoire by activity"
  on public.repertoire_songs for all to authenticated
  using (
    public.can_access_activity(activity_id)
    and public.is_singing_activity(activity_id)
  )
  with check (
    public.can_access_activity(activity_id)
    and public.is_singing_activity(activity_id)
  );

create policy "Staff can read session repertoire by activity"
  on public.session_repertoire_items for select to authenticated
  using (
    exists (
      select 1 from public.sessions s
      where s.id = session_repertoire_items.session_id
        and public.can_access_activity(s.activity_id)
        and public.is_singing_activity(s.activity_id)
    )
  );

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'repertoire_documents',
  'repertoire_documents',
  false,
  20971520,
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.can_access_repertoire_document(
  p_object_name text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  activity_folder text := (storage.foldername(p_object_name))[1];
  activity_id uuid;
begin
  if activity_folder !~
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  then
    return false;
  end if;
  activity_id := activity_folder::uuid;
  return public.can_access_activity(activity_id)
    and public.is_singing_activity(activity_id);
end;
$$;

revoke all on function public.can_access_repertoire_document(text)
  from public, anon;
grant execute on function public.can_access_repertoire_document(text)
  to authenticated;

create policy "Staff can read repertoire documents by activity"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'repertoire_documents'
    and public.can_access_repertoire_document(name)
  );

create policy "Staff can upload repertoire documents by activity"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'repertoire_documents'
    and public.can_access_repertoire_document(name)
  );

create policy "Staff can replace repertoire documents by activity"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'repertoire_documents'
    and public.can_access_repertoire_document(name)
  )
  with check (
    bucket_id = 'repertoire_documents'
    and public.can_access_repertoire_document(name)
  );

create policy "Staff can delete repertoire documents by activity"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'repertoire_documents'
    and public.can_access_repertoire_document(name)
  );

create or replace function public.save_session_playlist(
  p_session_id uuid,
  p_track_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_activity_id uuid;
begin
  select activity_id into session_activity_id
  from public.sessions
  where id = p_session_id;
  if not found then
    raise exception 'Session not found' using errcode = '23503';
  end if;
  if not public.can_access_activity(session_activity_id) then
    raise exception 'Not authorized to edit this session playlist'
      using errcode = '42501';
  end if;
  if public.is_singing_activity(session_activity_id) then
    raise exception 'Singing sessions use the separate repertoire'
      using errcode = '22023';
  end if;
  if exists (
    select track_id
    from unnest(coalesce(p_track_ids, array[]::uuid[])) as playlist(track_id)
    group by playlist.track_id
    having count(*) > 1
  ) then
    raise exception 'A track can only appear once in a session playlist'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from unnest(coalesce(p_track_ids, array[]::uuid[])) as playlist(track_id)
    left join public.tracks t on t.id = playlist.track_id
    where t.id is null or t.activity_id <> session_activity_id
  ) then
    raise exception 'Playlist tracks must belong to the session activity'
      using errcode = '22023';
  end if;

  delete from public.session_tracks where session_id = p_session_id;
  insert into public.session_tracks (session_id, track_id, position, played)
  select p_session_id, track_id, position - 1, false
  from unnest(coalesce(p_track_ids, array[]::uuid[]))
    with ordinality as playlist(track_id, position);
end;
$$;

revoke all on function public.save_session_playlist(uuid, uuid[])
  from public, anon;
grant execute on function public.save_session_playlist(uuid, uuid[])
  to authenticated;

create or replace function public.save_session_repertoire(
  p_session_id uuid,
  p_song_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_activity_id uuid;
begin
  select activity_id into session_activity_id
  from public.sessions
  where id = p_session_id;
  if not found then
    raise exception 'Session not found' using errcode = '23503';
  end if;
  if not public.can_access_activity(session_activity_id) then
    raise exception 'Not authorized to edit this session repertoire'
      using errcode = '42501';
  end if;
  if not public.is_singing_activity(session_activity_id) then
    raise exception 'This activity does not use singing repertoire'
      using errcode = '22023';
  end if;
  if exists (
    select song_id
    from unnest(coalesce(p_song_ids, array[]::uuid[])) as repertoire(song_id)
    group by repertoire.song_id
    having count(*) > 1
  ) then
    raise exception 'A song can only appear once in a session repertoire'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from unnest(coalesce(p_song_ids, array[]::uuid[])) as repertoire(song_id)
    left join public.repertoire_songs song on song.id = repertoire.song_id
    where song.id is null or song.activity_id <> session_activity_id
  ) then
    raise exception 'Repertoire songs must belong to the session activity'
      using errcode = '22023';
  end if;

  delete from public.session_repertoire_items
  where session_id = p_session_id;
  insert into public.session_repertoire_items (
    session_id, song_id, position, played
  )
  select p_session_id, song_id, position - 1, false
  from unnest(coalesce(p_song_ids, array[]::uuid[]))
    with ordinality as repertoire(song_id, position);
end;
$$;

revoke all on function public.save_session_repertoire(uuid, uuid[])
  from public, anon;
grant execute on function public.save_session_repertoire(uuid, uuid[])
  to authenticated;

create or replace function public.save_session_preparation(
  p_session_id uuid,
  p_preparation_notes text,
  p_equipment_checklist jsonb,
  p_track_ids uuid[],
  p_song_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_activity_id uuid;
begin
  select activity_id into session_activity_id
  from public.sessions
  where id = p_session_id;
  if not found then
    raise exception 'Session not found' using errcode = '23503';
  end if;
  if not public.can_access_activity(session_activity_id) then
    raise exception 'Not authorized to edit this session'
      using errcode = '42501';
  end if;
  if p_equipment_checklist is null
    or jsonb_typeof(p_equipment_checklist) <> 'array'
    or p_track_ids is null
    or p_song_ids is null then
    raise exception 'Session preparation is incomplete'
      using errcode = '22023';
  end if;

  if public.is_singing_activity(session_activity_id) then
    if cardinality(p_track_ids) > 0 then
      raise exception 'Singing sessions use the separate repertoire'
        using errcode = '22023';
    end if;
    perform public.save_session_repertoire(p_session_id, p_song_ids);
  else
    if cardinality(p_song_ids) > 0 then
      raise exception 'This activity does not use singing repertoire'
        using errcode = '22023';
    end if;
    perform public.save_session_playlist(p_session_id, p_track_ids);
  end if;

  update public.sessions
  set preparation_notes = nullif(trim(p_preparation_notes), ''),
      equipment_checklist = p_equipment_checklist,
      updated_at = now()
  where id = p_session_id;
end;
$$;

revoke all on function public.save_session_preparation(
  uuid, text, jsonb, uuid[], uuid[]
) from public, anon;
grant execute on function public.save_session_preparation(
  uuid, text, jsonb, uuid[], uuid[]
) to authenticated;

create or replace function public.close_session_with_summary(
  p_session_id uuid,
  p_absent_member_ids uuid[],
  p_played_track_ids uuid[],
  p_played_song_ids uuid[],
  p_follow_up_notes text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_activity_id uuid;
  session_starts_at timestamptz;
  absent_count integer;
  unique_absent_count integer;
begin
  select activity_id, starts_at
    into session_activity_id, session_starts_at
  from public.sessions
  where id = p_session_id
  for update;
  if not found then
    raise exception 'Session not found' using errcode = '23503';
  end if;
  if not public.can_access_activity(session_activity_id) then
    raise exception 'Not authorized to close this session'
      using errcode = '42501';
  end if;
  if exists (
    select 1 from public.sessions
    where id = p_session_id and status <> 'scheduled'
  ) then
    raise exception 'Only scheduled sessions can be closed'
      using errcode = '23514';
  end if;
  if p_absent_member_ids is null
    or p_played_track_ids is null
    or p_played_song_ids is null then
    raise exception 'Session summary is incomplete' using errcode = '22023';
  end if;

  select count(*), count(distinct member_id)
    into absent_count, unique_absent_count
  from unnest(p_absent_member_ids) as absent(member_id);
  if absent_count <> unique_absent_count then
    raise exception 'Absence list contains duplicates' using errcode = '22023';
  end if;
  if exists (
    select 1
    from unnest(p_absent_member_ids) as absent(member_id)
    left join public.members m
      on m.id = absent.member_id and m.is_active
    left join public.member_activities ma
      on ma.member_id = absent.member_id
      and ma.activity_id = session_activity_id
      and (ma.ended_at is null or ma.ended_at >=
        (session_starts_at at time zone 'Europe/Paris')::date)
    where m.id is null or ma.member_id is null
  ) then
    raise exception 'Absence list includes a member outside this activity'
      using errcode = '23514';
  end if;
  if exists (
    select 1
    from unnest(p_absent_member_ids) as absent(member_id)
    join public.attendances a
      on a.session_id = p_session_id and a.member_id = absent.member_id
  ) then
    raise exception 'A present member cannot also be marked absent'
      using errcode = '23514';
  end if;
  if exists (
    select 1
    from unnest(p_played_track_ids) as played(track_id)
    left join public.session_tracks st
      on st.session_id = p_session_id and st.track_id = played.track_id
    where st.track_id is null
  ) or exists (
    select 1
    from unnest(p_played_song_ids) as played(song_id)
    left join public.session_repertoire_items item
      on item.session_id = p_session_id and item.song_id = played.song_id
    where item.song_id is null
  ) then
    raise exception 'Played items must belong to the session plan'
      using errcode = '23514';
  end if;
  if exists (
    select track_id
    from unnest(p_played_track_ids) as played(track_id)
    group by played.track_id
    having count(*) > 1
  ) or exists (
    select song_id
    from unnest(p_played_song_ids) as played(song_id)
    group by played.song_id
    having count(*) > 1
  ) then
    raise exception 'Played item list contains duplicates'
      using errcode = '22023';
  end if;
  if (
    public.is_singing_activity(session_activity_id)
    and cardinality(p_played_track_ids) > 0
  ) or (
    not public.is_singing_activity(session_activity_id)
    and cardinality(p_played_song_ids) > 0
  ) then
    raise exception 'Played items do not match the session activity'
      using errcode = '23514';
  end if;

  insert into public.session_absences (
    session_id, member_id, confirmed_by
  )
  select p_session_id, absent.member_id, (select auth.uid())
  from unnest(p_absent_member_ids) as absent(member_id);

  update public.session_tracks
  set played = track_id = any(p_played_track_ids)
  where session_id = p_session_id;
  update public.session_repertoire_items
  set played = song_id = any(p_played_song_ids)
  where session_id = p_session_id;

  insert into public.session_closures (
    session_id, closed_by, follow_up_notes
  )
  values (
    p_session_id, (select auth.uid()), nullif(trim(p_follow_up_notes), '')
  );

  update public.sessions
  set status = 'completed', updated_at = now()
  where id = p_session_id;
end;
$$;

revoke all on function public.close_session_with_summary(
  uuid, uuid[], uuid[], uuid[], text
) from public, anon;
grant execute on function public.close_session_with_summary(
  uuid, uuid[], uuid[], uuid[], text
) to authenticated;

create or replace function public.record_completed_session_tracks()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    update public.tracks
    set last_played_at = new.starts_at,
        updated_at = now()
    where id in (
      select track_id
      from public.session_tracks
      where session_id = new.id and played
    );
  end if;
  return new;
end;
$$;

create or replace function public.mark_absence_corrected_on_check_in()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.session_absences
  set corrected_at = now(), corrected_by = (select auth.uid())
  where session_id = new.session_id
    and member_id = new.member_id
    and corrected_at is null;
  return new;
end;
$$;

revoke all on function public.mark_absence_corrected_on_check_in()
  from public, anon, authenticated;

create trigger attendance_corrects_confirmed_absence
  after insert on public.attendances
  for each row execute function public.mark_absence_corrected_on_check_in();

create or replace function public.record_completed_session_songs()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    update public.repertoire_songs
    set last_played_at = new.starts_at,
        updated_at = now()
    where id in (
      select song_id
      from public.session_repertoire_items
      where session_id = new.id and played
    );
  end if;
  return new;
end;
$$;

revoke all on function public.record_completed_session_songs()
  from public, anon, authenticated;

create trigger record_completed_session_songs
  after update of status on public.sessions
  for each row execute function public.record_completed_session_songs();
