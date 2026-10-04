create or replace function public.save_session_playlist(
  p_session_id uuid,
  p_track_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_app_role(array['admin', 'assistant']) then
    raise exception 'Not authorized to edit session playlists' using errcode = '42501';
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
  if not exists (select 1 from public.sessions where id = p_session_id) then
    raise exception 'Session not found' using errcode = '23503';
  end if;

  delete from public.session_tracks where session_id = p_session_id;
  insert into public.session_tracks (session_id, track_id, position)
  select p_session_id, track_id, position - 1
  from unnest(coalesce(p_track_ids, array[]::uuid[]))
    with ordinality as playlist(track_id, position);
end;
$$;

revoke all on function public.save_session_playlist(uuid, uuid[]) from public, anon;
grant execute on function public.save_session_playlist(uuid, uuid[]) to authenticated;
