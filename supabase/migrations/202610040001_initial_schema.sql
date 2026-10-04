create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  role text not null default 'assistant' check (role in ('admin', 'assistant')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.profiles where id = (select auth.uid())
$$;

create or replace function public.has_app_role(allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_app_role() = any (allowed_roles), false)
$$;

create table public.members (
  id uuid primary key default gen_random_uuid(),
  first_name text not null,
  last_name text not null,
  phone text,
  email text,
  birth_date date,
  photo_url text,
  membership_valid_until date,
  medical_certificate_url text,
  medical_certificate_valid_until date,
  emergency_contact_name text,
  emergency_contact_phone text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.pricing_settings (
  id smallint primary key default 1 check (id = 1),
  annual_membership_fee numeric(10, 2) not null default 20 check (annual_membership_fee >= 0),
  single_class_price numeric(10, 2) not null default 5 check (single_class_price >= 0),
  first_card_price numeric(10, 2) not null default 50 check (first_card_price >= 0),
  renewal_card_price numeric(10, 2) not null default 45 check (renewal_card_price >= 0),
  card_pass_count integer not null default 10 check (card_pass_count > 0),
  currency text not null default 'EUR' check (currency ~ '^[A-Z]{3}$'),
  updated_at timestamptz not null default now()
);

insert into public.pricing_settings (id) values (1)
on conflict (id) do nothing;

create table public.cards (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members (id) on delete restrict,
  purchase_number integer not null check (purchase_number > 0),
  total_passes integer not null default 10 check (total_passes > 0),
  remaining_passes integer not null default 10
    check (remaining_passes >= 0 and remaining_passes <= total_passes),
  purchase_price numeric(10, 2) not null check (purchase_price >= 0),
  purchased_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (member_id, purchase_number)
);

create index cards_member_remaining_idx on public.cards (member_id, remaining_passes, purchased_at);

create table public.tracks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  artist text not null default '',
  style text not null default 'other'
    check (style in ('salsa', 'merengue', 'reggaeton', 'bachata', 'cumbia', 'other')),
  duration_seconds integer not null default 0 check (duration_seconds >= 0),
  intensity text not null default 'moderate'
    check (intensity in ('warmUp', 'moderate', 'high', 'coolDown')),
  document_url text,
  document_type text check (document_type is null or document_type in ('photo', 'pdf')),
  teaching_notes text,
  last_played_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index tracks_title_idx on public.tracks (title);
create index tracks_last_played_idx on public.tracks (last_played_at);

create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  session_type text not null default 'class'
    check (session_type in ('class', 'event')),
  starts_at timestamptz not null,
  ends_at timestamptz,
  location text,
  capacity integer check (capacity is null or capacity >= 0),
  preparation_notes text,
  equipment_checklist jsonb not null default '[]'::jsonb
    check (jsonb_typeof(equipment_checklist) = 'array'),
  recurrence_rule jsonb,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'completed', 'cancelled')),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);

create index sessions_starts_at_idx on public.sessions (starts_at);
create index sessions_status_idx on public.sessions (status);

create table public.session_tracks (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id) on delete cascade,
  track_id uuid not null references public.tracks (id) on delete restrict,
  position integer not null check (position >= 0),
  notes text,
  created_at timestamptz not null default now(),
  unique (session_id, position)
);

create index session_tracks_track_id_idx on public.session_tracks (track_id);

create table public.attendances (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id) on delete cascade,
  member_id uuid not null references public.members (id) on delete restrict,
  card_id uuid references public.cards (id) on delete restrict,
  checked_in_at timestamptz not null default now(),
  checked_in_by uuid references public.profiles (id) on delete set null,
  offline_operation_id uuid unique,
  notes text,
  unique (session_id, member_id)
);

create index attendances_member_checked_in_idx
  on public.attendances (member_id, checked_in_at desc);
create index attendances_session_id_idx on public.attendances (session_id);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members (id) on delete restrict,
  card_id uuid references public.cards (id) on delete set null,
  amount numeric(10, 2) not null check (amount >= 0),
  payment_type text not null
    check (payment_type in ('membership', 'single_class', 'class_card', 'event', 'other')),
  payment_method text not null
    check (payment_method in ('cash', 'cheque', 'bank_transfer', 'card')),
  paid_at timestamptz not null default now(),
  receipt_number text unique,
  receipt_url text,
  notes text,
  recorded_by uuid references public.profiles (id) on delete set null,
  offline_operation_id uuid unique,
  created_at timestamptz not null default now()
);

create index payments_paid_at_idx on public.payments (paid_at desc);
create index payments_member_id_idx on public.payments (member_id);

create table public.event_registrations (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id) on delete cascade,
  full_name text not null,
  email text,
  phone text,
  amount_paid numeric(10, 2) not null default 0 check (amount_paid >= 0),
  payment_method text check (
    payment_method is null or payment_method in ('cash', 'cheque', 'bank_transfer', 'card')
  ),
  registered_at timestamptz not null default now(),
  checked_in_at timestamptz,
  notes text,
  offline_operation_id uuid unique
);

create index event_registrations_session_id_idx on public.event_registrations (session_id);

create or replace function public.check_in_member(
  p_session_id uuid,
  p_member_id uuid,
  p_card_id uuid default null,
  p_offline_operation_id uuid default null
)
returns public.attendances
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_attendance public.attendances;
  checked_in public.attendances;
  card_remaining integer;
begin
  if not public.has_app_role(array['admin', 'assistant']) then
    raise exception 'Not authorized to check in members' using errcode = '42501';
  end if;

  select * into existing_attendance
  from public.attendances
  where session_id = p_session_id and member_id = p_member_id;

  if found then
    return existing_attendance;
  end if;

  if p_card_id is not null then
    select remaining_passes into card_remaining
    from public.cards
    where id = p_card_id and member_id = p_member_id
    for update;

    if not found then
      raise exception 'Card does not belong to this member' using errcode = '23503';
    end if;
    if card_remaining < 1 then
      raise exception 'Card has no remaining passes' using errcode = '23514';
    end if;

    update public.cards
    set remaining_passes = remaining_passes - 1
    where id = p_card_id;
  end if;

  insert into public.attendances (
    session_id, member_id, card_id, checked_in_by, offline_operation_id
  )
  values (
    p_session_id, p_member_id, p_card_id, (select auth.uid()), p_offline_operation_id
  )
  returning * into checked_in;

  return checked_in;
end;
$$;

revoke all on function public.check_in_member(uuid, uuid, uuid, uuid) from public;
grant execute on function public.check_in_member(uuid, uuid, uuid, uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.members enable row level security;
alter table public.pricing_settings enable row level security;
alter table public.cards enable row level security;
alter table public.tracks enable row level security;
alter table public.sessions enable row level security;
alter table public.session_tracks enable row level security;
alter table public.attendances enable row level security;
alter table public.payments enable row level security;
alter table public.event_registrations enable row level security;

create policy "Users can read own profile; admins can read all"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.has_app_role(array['admin']));
create policy "Admins can insert profiles"
  on public.profiles for insert to authenticated
  with check (public.has_app_role(array['admin']));
create policy "Users can update own profile; admins can update all"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()) or public.has_app_role(array['admin']))
  with check (
    public.has_app_role(array['admin'])
    or (id = (select auth.uid()) and role = public.current_app_role())
  );
create policy "Admins can delete profiles"
  on public.profiles for delete to authenticated
  using (public.has_app_role(array['admin']));

create policy "Staff can read members"
  on public.members for select to authenticated
  using (public.has_app_role(array['admin', 'assistant']));
create policy "Staff can create and update members"
  on public.members for all to authenticated
  using (public.has_app_role(array['admin', 'assistant']))
  with check (public.has_app_role(array['admin', 'assistant']));

create policy "Staff can read pricing"
  on public.pricing_settings for select to authenticated
  using (public.has_app_role(array['admin', 'assistant']));
create policy "Admins can manage pricing"
  on public.pricing_settings for all to authenticated
  using (public.has_app_role(array['admin']))
  with check (public.has_app_role(array['admin']));

create policy "Staff can read cards"
  on public.cards for select to authenticated
  using (public.has_app_role(array['admin', 'assistant']));
create policy "Admins can manage cards"
  on public.cards for all to authenticated
  using (public.has_app_role(array['admin']))
  with check (public.has_app_role(array['admin']));

create policy "Staff can read tracks"
  on public.tracks for select to authenticated
  using (public.has_app_role(array['admin', 'assistant']));
create policy "Staff can manage tracks"
  on public.tracks for all to authenticated
  using (public.has_app_role(array['admin', 'assistant']))
  with check (public.has_app_role(array['admin', 'assistant']));

create policy "Staff can read sessions"
  on public.sessions for select to authenticated
  using (public.has_app_role(array['admin', 'assistant']));
create policy "Staff can manage sessions"
  on public.sessions for all to authenticated
  using (public.has_app_role(array['admin', 'assistant']))
  with check (public.has_app_role(array['admin', 'assistant']));

create policy "Staff can read session tracks"
  on public.session_tracks for select to authenticated
  using (public.has_app_role(array['admin', 'assistant']));
create policy "Staff can manage session tracks"
  on public.session_tracks for all to authenticated
  using (public.has_app_role(array['admin', 'assistant']))
  with check (public.has_app_role(array['admin', 'assistant']));

create policy "Staff can read attendance"
  on public.attendances for select to authenticated
  using (public.has_app_role(array['admin', 'assistant']));
create policy "Admins can manage attendance"
  on public.attendances for all to authenticated
  using (public.has_app_role(array['admin']))
  with check (public.has_app_role(array['admin']));

create policy "Staff can read payments"
  on public.payments for select to authenticated
  using (public.has_app_role(array['admin', 'assistant']));
create policy "Staff can register payments"
  on public.payments for insert to authenticated
  with check (public.has_app_role(array['admin', 'assistant']));
create policy "Admins can update or delete payments"
  on public.payments for update to authenticated
  using (public.has_app_role(array['admin']))
  with check (public.has_app_role(array['admin']));
create policy "Admins can delete payments"
  on public.payments for delete to authenticated
  using (public.has_app_role(array['admin']));

create policy "Staff can manage event registrations"
  on public.event_registrations for all to authenticated
  using (public.has_app_role(array['admin', 'assistant']))
  with check (public.has_app_role(array['admin', 'assistant']));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('member_photos', 'member_photos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp']),
  ('choreography_docs', 'choreography_docs', false, 20971520, array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Staff can read member photos"
  on storage.objects for select to authenticated
  using (bucket_id = 'member_photos' and public.has_app_role(array['admin', 'assistant']));
create policy "Staff can upload member photos"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'member_photos' and public.has_app_role(array['admin', 'assistant']));
create policy "Staff can update member photos"
  on storage.objects for update to authenticated
  using (bucket_id = 'member_photos' and public.has_app_role(array['admin', 'assistant']))
  with check (bucket_id = 'member_photos' and public.has_app_role(array['admin', 'assistant']));
create policy "Admins can delete member photos"
  on storage.objects for delete to authenticated
  using (bucket_id = 'member_photos' and public.has_app_role(array['admin']));

create policy "Staff can read choreography documents"
  on storage.objects for select to authenticated
  using (bucket_id = 'choreography_docs' and public.has_app_role(array['admin', 'assistant']));
create policy "Staff can upload choreography documents"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'choreography_docs' and public.has_app_role(array['admin', 'assistant']));
create policy "Staff can update choreography documents"
  on storage.objects for update to authenticated
  using (bucket_id = 'choreography_docs' and public.has_app_role(array['admin', 'assistant']))
  with check (bucket_id = 'choreography_docs' and public.has_app_role(array['admin', 'assistant']));
create policy "Admins can delete choreography documents"
  on storage.objects for delete to authenticated
  using (bucket_id = 'choreography_docs' and public.has_app_role(array['admin']));
