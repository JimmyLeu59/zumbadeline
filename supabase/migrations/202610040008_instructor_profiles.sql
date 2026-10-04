alter table public.profiles
  add column if not exists teaching_dances text[] not null default '{}';

drop policy if exists "Users can read own profile; admins can read all"
  on public.profiles;

create policy "Staff can read staff profiles"
  on public.profiles for select to authenticated
  using (public.has_app_role(array['admin', 'assistant']));
