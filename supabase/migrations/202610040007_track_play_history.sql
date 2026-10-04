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
      where session_id = new.id
    );
  end if;
  return new;
end;
$$;

revoke all on function public.record_completed_session_tracks()
  from public, anon, authenticated;

drop trigger if exists record_completed_session_tracks on public.sessions;
create trigger record_completed_session_tracks
  after update of status on public.sessions
  for each row execute function public.record_completed_session_tracks();
