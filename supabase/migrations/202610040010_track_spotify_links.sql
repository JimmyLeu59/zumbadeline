alter table public.tracks
  add column if not exists spotify_url text;
