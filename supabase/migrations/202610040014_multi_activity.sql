create table public.activities (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (length(trim(name)) > 0),
  color_code text not null default '#6750A4'
    check (color_code ~ '^#[0-9A-Fa-f]{6}$'),
  icon text not null default 'fitness_center',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.activities (id, name, color_code, icon)
values ('00000000-0000-0000-0000-000000000001', 'Zumba', '#E91E63', 'fitness_center')
on conflict (id) do nothing;

alter table public.profiles
  drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('admin', 'president', 'treasurer', 'assistant', 'instructor'));
alter table public.profiles
  add column activity_id_access uuid references public.activities (id) on delete set null;

alter table public.members
  add column status text
    check (status in ('active', 'inactive', 'archived'));
update public.members
set status = case when is_active then 'active' else 'inactive' end;
alter table public.members
  alter column status set not null;

create table public.member_activities (
  member_id uuid not null references public.members (id) on delete cascade,
  activity_id uuid not null references public.activities (id) on delete restrict,
  enrolled_at date not null default current_date,
  ended_at date,
  created_at timestamptz not null default now(),
  primary key (member_id, activity_id),
  check (ended_at is null or ended_at >= enrolled_at)
);

insert into public.member_activities (member_id, activity_id)
select id, '00000000-0000-0000-0000-000000000001'
from public.members
on conflict (member_id, activity_id) do nothing;

alter table public.tracks
  add column activity_id uuid references public.activities (id) on delete restrict
    default '00000000-0000-0000-0000-000000000001',
  add column local_document_path text;
update public.tracks
set activity_id = '00000000-0000-0000-0000-000000000001'
where activity_id is null;
alter table public.tracks alter column activity_id set not null;

create table public.recurring_events (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities (id) on delete restrict,
  is_active boolean not null default true,
  title text not null check (length(trim(title)) > 0),
  session_type text not null default 'class'
    check (session_type in ('class', 'event')),
  starts_at timestamptz not null,
  ends_at timestamptz,
  time_zone text not null default 'Europe/Paris',
  recurrence_rule jsonb not null
    check (jsonb_typeof(recurrence_rule) = 'object'),
  repeats_until date,
  location text,
  capacity integer check (capacity is null or capacity >= 0),
  preparation_notes text,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);

alter table public.sessions
  add column activity_id uuid references public.activities (id) on delete restrict
    default '00000000-0000-0000-0000-000000000001',
  add column recurring_event_id uuid
    references public.recurring_events (id) on delete restrict,
  add column occurrence_key timestamptz;
update public.sessions
set activity_id = '00000000-0000-0000-0000-000000000001'
where activity_id is null;
alter table public.sessions alter column activity_id set not null;

create unique index sessions_series_occurrence_idx
  on public.sessions (recurring_event_id, occurrence_key)
  where recurring_event_id is not null and occurrence_key is not null;
create index sessions_activity_starts_at_idx
  on public.sessions (activity_id, starts_at);
create index recurring_events_activity_idx
  on public.recurring_events (activity_id, starts_at);

alter table public.cards
  drop constraint if exists cards_member_id_purchase_number_key;
alter table public.cards
  add column activity_id uuid not null
    references public.activities (id) on delete restrict
    default '00000000-0000-0000-0000-000000000001',
  add column price_tier text not null default 'standard'
    check (price_tier in ('standard', 'loyalty'));
alter table public.cards
  add constraint cards_member_activity_purchase_number_key
  unique (member_id, activity_id, purchase_number);
update public.cards
set price_tier = case when purchase_number = 1 then 'standard' else 'loyalty' end;

alter table public.payments
  add column activity_id uuid references public.activities (id) on delete restrict,
  add column expense_report_id uuid;

update public.payments
set activity_id = '00000000-0000-0000-0000-000000000001'
where payment_type <> 'membership';

create table public.expense_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete restrict,
  activity_id uuid references public.activities (id) on delete restrict,
  amount numeric(10, 2) not null check (amount > 0),
  description text not null check (length(trim(description)) > 0),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'reimbursed')),
  receipt_path text,
  incurred_at date not null default current_date,
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (status = 'pending' and reviewed_at is null)
    or (status <> 'pending' and reviewed_at is not null)
  )
);

alter table public.payments
  add constraint payments_expense_report_id_fkey
  foreign key (expense_report_id) references public.expense_reports (id) on delete set null;

create index member_activities_activity_idx
  on public.member_activities (activity_id, member_id);
create index cards_activity_purchased_idx
  on public.cards (activity_id, purchased_at desc);
create index payments_activity_paid_at_idx
  on public.payments (activity_id, paid_at desc);
create index expense_reports_activity_status_idx
  on public.expense_reports (activity_id, status, incurred_at desc);

create or replace function public.can_access_activity(p_activity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when public.has_app_role(array['admin', 'president', 'treasurer', 'assistant'])
      then true
    when p_activity_id is null then false
    else exists (
      select 1
      from public.profiles
      where id = (select auth.uid())
        and role = 'instructor'
        and activity_id_access = p_activity_id
    )
  end
$$;

revoke all on function public.can_access_activity(uuid) from public, anon;
grant execute on function public.can_access_activity(uuid) to authenticated;

create or replace function public.current_activity_access()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select activity_id_access
  from public.profiles
  where id = (select auth.uid())
$$;

revoke all on function public.current_activity_access() from public, anon;
grant execute on function public.current_activity_access() to authenticated;

create or replace function public.sync_member_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status is null then
      new.status := case when new.is_active then 'active' else 'inactive' end;
    else
      new.is_active := new.status = 'active';
    end if;
  elsif new.is_active is distinct from old.is_active then
    new.status := case when new.is_active then 'active' else 'inactive' end;
  elsif new.status is distinct from old.status then
    new.is_active := new.status = 'active';
  end if;
  return new;
end;
$$;

create trigger members_sync_status
before insert or update of is_active, status on public.members
for each row execute function public.sync_member_status();

drop policy if exists "Users can update own profile; admins can update all"
  on public.profiles;
create policy "Users can update own profile; admins can update all"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()) or public.has_app_role(array['admin']))
  with check (
    public.has_app_role(array['admin'])
    or (
      id = (select auth.uid())
      and role = public.current_app_role()
      and activity_id_access is not distinct from public.current_activity_access()
    )
  );

alter table public.activities enable row level security;
alter table public.member_activities enable row level security;
alter table public.recurring_events enable row level security;
alter table public.expense_reports enable row level security;

drop policy if exists "Staff can read members" on public.members;
create policy "Staff can read members in accessible activities"
  on public.members for select to authenticated
  using (
    public.has_app_role(array['admin', 'president', 'treasurer', 'assistant'])
    or exists (
      select 1 from public.member_activities ma
      where ma.member_id = members.id
        and public.can_access_activity(ma.activity_id)
    )
  );
drop policy if exists "Staff can create and update members" on public.members;
create policy "Managers can manage members"
  on public.members for all to authenticated
  using (public.has_app_role(array['admin', 'president', 'assistant']))
  with check (public.has_app_role(array['admin', 'president', 'assistant']));

create policy "Authenticated users can read activities"
  on public.activities for select to authenticated using (true);
create policy "Admins can manage activities"
  on public.activities for all to authenticated
  using (public.has_app_role(array['admin']))
  with check (public.has_app_role(array['admin']));

create policy "Staff can read member activity assignments"
  on public.member_activities for select to authenticated
  using (
    public.has_app_role(array['admin', 'president', 'treasurer', 'assistant'])
    or public.can_access_activity(activity_id)
  );
create policy "Managers can manage member activity assignments"
  on public.member_activities for all to authenticated
  using (public.has_app_role(array['admin', 'president', 'assistant']))
  with check (public.has_app_role(array['admin', 'president', 'assistant']));

drop policy if exists "Staff can read tracks" on public.tracks;
create policy "Staff can read tracks in accessible activities"
  on public.tracks for select to authenticated
  using (public.can_access_activity(activity_id));
drop policy if exists "Staff can manage tracks" on public.tracks;
create policy "Staff can manage tracks in accessible activities"
  on public.tracks for all to authenticated
  using (
    public.has_app_role(array['admin', 'president', 'assistant'])
    or public.can_access_activity(activity_id)
  )
  with check (
    public.has_app_role(array['admin', 'president', 'assistant'])
    or public.can_access_activity(activity_id)
  );

drop policy if exists "Staff can read session tracks" on public.session_tracks;
create policy "Staff can read session tracks in accessible activities"
  on public.session_tracks for select to authenticated
  using (
    exists (
      select 1 from public.sessions s
      where s.id = session_tracks.session_id
        and public.can_access_activity(s.activity_id)
    )
  );
drop policy if exists "Staff can manage session tracks" on public.session_tracks;
create policy "Staff can manage session tracks in accessible activities"
  on public.session_tracks for all to authenticated
  using (
    exists (
      select 1 from public.sessions s
      where s.id = session_tracks.session_id
        and public.can_access_activity(s.activity_id)
    )
  )
  with check (
    exists (
      select 1 from public.sessions s
      where s.id = session_tracks.session_id
        and public.can_access_activity(s.activity_id)
    )
  );

drop policy if exists "Staff can read event instructors" on public.session_instructors;
create policy "Staff can read instructors in accessible activities"
  on public.session_instructors for select to authenticated
  using (
    exists (
      select 1 from public.sessions s
      where s.id = session_instructors.session_id
        and public.can_access_activity(s.activity_id)
    )
  );

drop policy if exists "Staff can read sessions" on public.sessions;
create policy "Staff can read sessions in accessible activities"
  on public.sessions for select to authenticated
  using (public.can_access_activity(activity_id));
drop policy if exists "Staff can create sessions" on public.sessions;
create policy "Staff can create sessions in accessible activities"
  on public.sessions for insert to authenticated
  with check (
    public.has_app_role(array['admin', 'president', 'assistant'])
    or public.can_access_activity(activity_id)
  );
drop policy if exists "Staff can update sessions" on public.sessions;
create policy "Staff can update sessions in accessible activities"
  on public.sessions for update to authenticated
  using (
    public.has_app_role(array['admin', 'president', 'assistant'])
    or public.can_access_activity(activity_id)
  )
  with check (
    public.has_app_role(array['admin', 'president', 'assistant'])
    or public.can_access_activity(activity_id)
  );

create policy "Staff can read recurring events in accessible activities"
  on public.recurring_events for select to authenticated
  using (public.can_access_activity(activity_id));
create policy "Staff can create recurring events in accessible activities"
  on public.recurring_events for insert to authenticated
  with check (
    public.has_app_role(array['admin', 'president', 'assistant'])
    or public.can_access_activity(activity_id)
  );
create policy "Staff can update recurring events in accessible activities"
  on public.recurring_events for update to authenticated
  using (
    public.has_app_role(array['admin', 'president', 'assistant'])
    or public.can_access_activity(activity_id)
  )
  with check (
    public.has_app_role(array['admin', 'president', 'assistant'])
    or public.can_access_activity(activity_id)
  );
drop policy if exists "Staff can read cards" on public.cards;
create policy "Staff can read cards in accessible activities"
  on public.cards for select to authenticated
  using (public.can_access_activity(activity_id));
drop policy if exists "Admins can manage cards" on public.cards;
create policy "Managers can manage cards in accessible activities"
  on public.cards for all to authenticated
  using (public.has_app_role(array['admin', 'president', 'assistant']))
  with check (public.has_app_role(array['admin', 'president', 'assistant']));

drop policy if exists "Staff can read payments" on public.payments;
create policy "Staff can read payments by activity"
  on public.payments for select to authenticated
  using (
    public.can_access_activity(activity_id)
    or (
      activity_id is null
      and public.has_app_role(array['admin', 'president', 'treasurer', 'assistant'])
    )
  );
drop policy if exists "Staff can register payments" on public.payments;
create policy "Staff can register payments by activity"
  on public.payments for insert to authenticated
  with check (
    (activity_id is not null and public.can_access_activity(activity_id))
    or (
      activity_id is null
      and public.has_app_role(array['admin', 'president', 'treasurer', 'assistant'])
    )
  );
drop policy if exists "Admins can update or delete payments" on public.payments;
drop policy if exists "Admins can delete payments" on public.payments;
create policy "Finance managers can update payments"
  on public.payments for update to authenticated
  using (public.has_app_role(array['admin', 'president', 'treasurer']))
  with check (public.has_app_role(array['admin', 'president', 'treasurer']));
create policy "Finance managers can delete payments"
  on public.payments for delete to authenticated
  using (public.has_app_role(array['admin', 'president', 'treasurer']));

drop policy if exists "Staff can read attendance" on public.attendances;
create policy "Staff can read attendance in accessible activities"
  on public.attendances for select to authenticated
  using (
    exists (
      select 1 from public.sessions s
      where s.id = attendances.session_id
        and public.can_access_activity(s.activity_id)
    )
  );
drop policy if exists "Admins can manage attendance" on public.attendances;
create policy "Staff can manage attendance in accessible activities"
  on public.attendances for all to authenticated
  using (
    exists (
      select 1 from public.sessions s
      where s.id = attendances.session_id
        and (
          public.has_app_role(array['admin', 'president', 'assistant'])
          or public.can_access_activity(s.activity_id)
        )
    )
  )
  with check (
    exists (
      select 1 from public.sessions s
      where s.id = attendances.session_id
        and (
          public.has_app_role(array['admin', 'president', 'assistant'])
          or public.can_access_activity(s.activity_id)
        )
    )
  );

drop policy if exists "Staff can manage event registrations" on public.event_registrations;
create policy "Staff can manage event registrations by activity"
  on public.event_registrations for all to authenticated
  using (
    exists (
      select 1 from public.sessions s
      where s.id = event_registrations.session_id
        and public.can_access_activity(s.activity_id)
    )
  )
  with check (
    exists (
      select 1 from public.sessions s
      where s.id = event_registrations.session_id
        and public.can_access_activity(s.activity_id)
    )
  );

create policy "Users can read own expenses; finance can read all"
  on public.expense_reports for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.has_app_role(array['admin', 'president', 'treasurer'])
  );
create policy "Users can submit expenses for accessible activities"
  on public.expense_reports for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
    and (
      (activity_id is not null and public.can_access_activity(activity_id))
      or (
        activity_id is null
        and public.has_app_role(
          array['admin', 'president', 'treasurer', 'assistant']
        )
      )
    )
  );
create policy "Finance can review expenses"
  on public.expense_reports for update to authenticated
  using (public.has_app_role(array['admin', 'president', 'treasurer']))
  with check (public.has_app_role(array['admin', 'president', 'treasurer']));
create policy "Admins can delete pending expenses"
  on public.expense_reports for delete to authenticated
  using (
    status = 'pending'
    and public.has_app_role(array['admin', 'president'])
  );

create or replace function public.check_in_member_with_payment(
  p_session_id uuid,
  p_member_id uuid,
  p_card_id uuid,
  p_payment_method text,
  p_offline_operation_id uuid
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
  single_price numeric(10, 2);
  session_activity_id uuid;
begin
  select activity_id into session_activity_id
  from public.sessions
  where id = p_session_id;
  if not found then
    raise exception 'Session not found' using errcode = '23503';
  end if;
  if not public.can_access_activity(session_activity_id) then
    raise exception 'Not authorized to check in members for this activity'
      using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.members where id = p_member_id and is_active
  ) then
    raise exception 'Active member not found' using errcode = '23503';
  end if;
  if not exists (
    select 1 from public.member_activities
    where member_id = p_member_id and activity_id = session_activity_id
      and (ended_at is null or ended_at >= current_date)
  ) then
    raise exception 'Member is not enrolled in this activity'
      using errcode = '23514';
  end if;
  if p_payment_method not in ('cash', 'cheque', 'bank_transfer', 'card') then
    raise exception 'Invalid payment method' using errcode = '22023';
  end if;

  select * into existing_attendance
  from public.attendances
  where session_id = p_session_id and member_id = p_member_id;
  if found then return existing_attendance; end if;

  if p_card_id is not null then
    select remaining_passes into card_remaining
    from public.cards
    where id = p_card_id
      and member_id = p_member_id
      and activity_id = session_activity_id
    for update;
    if not found then
      raise exception 'Card does not belong to this member and activity'
        using errcode = '23503';
    end if;
    if card_remaining < 1 then
      raise exception 'Card has no remaining passes' using errcode = '23514';
    end if;
    update public.cards set remaining_passes = remaining_passes - 1
    where id = p_card_id;
  else
    select single_class_price into single_price
    from public.pricing_settings where id = 1;
    if not found then
      raise exception 'Pricing settings are not configured' using errcode = 'P0002';
    end if;

    insert into public.payments (
      member_id, activity_id, amount, payment_type, payment_method, paid_at,
      receipt_number, recorded_by, offline_operation_id
    )
    values (
      p_member_id, session_activity_id, single_price, 'single_class',
      p_payment_method, now(),
      'ZUM-' || to_char(now() at time zone 'UTC', 'YYYYMMDD') || '-' ||
        upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
      (select auth.uid()), p_offline_operation_id
    );
  end if;

  insert into public.attendances (
    session_id, member_id, card_id, checked_in_by, offline_operation_id
  )
  values (
    p_session_id, p_member_id, p_card_id, (select auth.uid()),
    p_offline_operation_id
  )
  returning * into checked_in;
  return checked_in;
end;
$$;

revoke all on function public.check_in_member_with_payment(uuid, uuid, uuid, text, uuid)
  from public, anon;
grant execute on function public.check_in_member_with_payment(uuid, uuid, uuid, text, uuid)
  to authenticated;

create or replace function public.purchase_activity_card(
  p_member_id uuid,
  p_activity_id uuid,
  p_price_tier text,
  p_payment_method text,
  p_offline_operation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  purchase_count integer;
  pass_count integer;
  purchase_price numeric(10, 2);
  created_card public.cards;
  created_payment public.payments;
begin
  if not public.can_access_activity(p_activity_id) then
    raise exception 'Not authorized to sell cards for this activity'
      using errcode = '42501';
  end if;
  if p_price_tier not in ('standard', 'loyalty')
    or p_payment_method not in ('cash', 'cheque', 'bank_transfer', 'card') then
    raise exception 'Invalid card purchase details' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.member_activities
    where member_id = p_member_id and activity_id = p_activity_id
      and (ended_at is null or ended_at >= current_date)
  ) then
    raise exception 'Member is not enrolled in this activity'
      using errcode = '23514';
  end if;

  if p_offline_operation_id is not null then
    select * into created_payment
    from public.payments
    where offline_operation_id = p_offline_operation_id;
    if found then
      if created_payment.member_id <> p_member_id
        or created_payment.activity_id is distinct from p_activity_id
        or created_payment.payment_type <> 'class_card' then
        raise exception 'Offline operation id was used for another transaction'
          using errcode = '23505';
      end if;
      select * into created_card from public.cards where id = created_payment.card_id;
      return jsonb_build_object(
        'payment', to_jsonb(created_payment),
        'card', to_jsonb(created_card)
      );
    end if;
  end if;

  perform 1 from public.members
  where id = p_member_id and is_active
  for update;
  if not found then
    raise exception 'Active member not found' using errcode = '23503';
  end if;

  select count(*) into purchase_count
  from public.cards
  where member_id = p_member_id and activity_id = p_activity_id;
  select card_pass_count,
    case
      when p_price_tier = 'standard' then first_card_price
      else renewal_card_price
    end
  into pass_count, purchase_price
  from public.pricing_settings where id = 1;
  if not found then
    raise exception 'Pricing settings are not configured' using errcode = 'P0002';
  end if;

  insert into public.cards (
    member_id, activity_id, purchase_number, total_passes, remaining_passes,
    purchase_price, price_tier
  )
  values (
    p_member_id, p_activity_id, purchase_count + 1, pass_count, pass_count,
    purchase_price, p_price_tier
  )
  returning * into created_card;

  insert into public.payments (
    member_id, activity_id, card_id, amount, payment_type, payment_method,
    paid_at, receipt_number, recorded_by, offline_operation_id
  )
  values (
    p_member_id, p_activity_id, created_card.id, purchase_price, 'class_card',
    p_payment_method, now(),
    'ZUM-' || to_char(now() at time zone 'UTC', 'YYYYMMDD') || '-' ||
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    (select auth.uid()), p_offline_operation_id
  )
  returning * into created_payment;

  return jsonb_build_object(
    'payment', to_jsonb(created_payment),
    'card', to_jsonb(created_card)
  );
end;
$$;

revoke all on function public.purchase_activity_card(uuid, uuid, text, text, uuid)
  from public, anon;
grant execute on function public.purchase_activity_card(uuid, uuid, text, text, uuid)
  to authenticated;

create or replace function public.record_activity_payment(
  p_member_id uuid,
  p_activity_id uuid,
  p_payment_type text,
  p_payment_method text,
  p_amount numeric,
  p_notes text default null,
  p_offline_operation_id uuid default null
)
returns public.payments
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_payment public.payments;
  configured_amount numeric(10, 2);
begin
  if not public.can_access_activity(p_activity_id) then
    raise exception 'Not authorized to record payments for this activity'
      using errcode = '42501';
  end if;
  if p_payment_type not in ('single_class', 'event', 'other')
    or p_payment_method not in ('cash', 'cheque', 'bank_transfer', 'card')
    or p_amount < 0 then
    raise exception 'Invalid payment details' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.member_activities
    where member_id = p_member_id and activity_id = p_activity_id
      and (ended_at is null or ended_at >= current_date)
  ) then
    raise exception 'Member is not enrolled in this activity'
      using errcode = '23514';
  end if;
  if p_payment_type = 'single_class' then
    select single_class_price into configured_amount
    from public.pricing_settings where id = 1;
    if not found then
      raise exception 'Pricing settings are not configured' using errcode = 'P0002';
    end if;
    if p_amount <> configured_amount then
      raise exception 'Payment amount does not match the configured price'
        using errcode = '22023';
    end if;
  end if;

  if p_offline_operation_id is not null then
    select * into created_payment
    from public.payments
    where offline_operation_id = p_offline_operation_id;
    if found then
      if created_payment.member_id <> p_member_id
        or created_payment.activity_id is distinct from p_activity_id
        or created_payment.payment_type <> p_payment_type then
        raise exception 'Offline operation id was used for another transaction'
          using errcode = '23505';
      end if;
      return created_payment;
    end if;
  end if;

  insert into public.payments (
    member_id, activity_id, amount, payment_type, payment_method, paid_at,
    receipt_number, notes, recorded_by, offline_operation_id
  )
  values (
    p_member_id, p_activity_id, p_amount, p_payment_type, p_payment_method,
    now(),
    'ZUM-' || to_char(now() at time zone 'UTC', 'YYYYMMDD') || '-' ||
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    p_notes, (select auth.uid()), p_offline_operation_id
  )
  returning * into created_payment;
  return created_payment;
end;
$$;

revoke all on function public.record_activity_payment(
  uuid, uuid, text, text, numeric, text, uuid
) from public, anon;
grant execute on function public.record_activity_payment(
  uuid, uuid, text, text, numeric, text, uuid
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
    update public.sessions
    set status = 'cancelled', updated_at = now()
    where recurring_event_id = series_id
      and starts_at >= now()
      and status <> 'cancelled';
  else
    update public.sessions
    set status = 'cancelled', updated_at = now()
    where id = p_session_id;
  end if;
end;
$$;

revoke all on function public.delete_recurring_occurrence(uuid, boolean)
  from public, anon;
grant execute on function public.delete_recurring_occurrence(uuid, boolean)
  to authenticated;

grant select, insert, update, delete on public.activities to authenticated;
grant select, insert, update, delete on public.member_activities to authenticated;
grant select, insert, update, delete on public.recurring_events to authenticated;
grant select, insert, update, delete on public.expense_reports to authenticated;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'expense_receipts', 'expense_receipts', false, 10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Users can upload their own expense receipts"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'expense_receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
create policy "Users and finance can read expense receipts"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'expense_receipts'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or public.has_app_role(array['admin', 'president', 'treasurer'])
    )
  );
create policy "Users can replace their own expense receipts"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'expense_receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'expense_receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

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
  session_activity_id uuid;
begin
  if p_session is null
    or jsonb_typeof(p_session) <> 'object'
    or p_session->>'session_type' <> 'event'
    or coalesce(trim(p_session->>'title'), '') = ''
    or coalesce(trim(p_session->>'starts_at'), '') = ''
    or coalesce(trim(p_session->>'activity_id'), '') = '' then
    raise exception 'Invalid event details' using errcode = '22023';
  end if;
  session_activity_id := (p_session->>'activity_id')::uuid;
  if not public.can_access_activity(session_activity_id) then
    raise exception 'Not authorized to assign event instructors'
      using errcode = '42501';
  end if;
  if p_assignments is null or jsonb_typeof(p_assignments) <> 'array' then
    raise exception 'Assignments must be a JSON array' using errcode = '22023';
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
    id, title, session_type, starts_at, ends_at, location, capacity,
    preparation_notes, equipment_checklist, status, activity_id, created_by
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
    coalesce(nullif(p_session->>'status', ''), 'scheduled'),
    session_activity_id,
    (select auth.uid())
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
    activity_id = excluded.activity_id,
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

create or replace function public.purchase_activity_card_and_check_in(
  p_session_id uuid,
  p_member_id uuid,
  p_price_tier text,
  p_payment_method text,
  p_offline_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_activity_id uuid;
  sale jsonb;
  created_attendance public.attendances;
begin
  select activity_id into session_activity_id
  from public.sessions
  where id = p_session_id;
  if not found then
    raise exception 'Session not found' using errcode = '23503';
  end if;
  if not public.can_access_activity(session_activity_id) then
    raise exception 'Not authorized to check in members for this activity'
      using errcode = '42501';
  end if;

  select * into created_attendance
  from public.attendances
  where session_id = p_session_id and member_id = p_member_id;
  if found then
    return jsonb_build_object(
      'attendance', to_jsonb(created_attendance),
      'already_checked_in', true
    );
  end if;

  sale := public.purchase_activity_card(
    p_member_id,
    session_activity_id,
    p_price_tier,
    p_payment_method,
    p_offline_operation_id
  );
  select public.check_in_member_with_payment(
    p_session_id,
    p_member_id,
    ((sale->'card')->>'id')::uuid,
    p_payment_method,
    p_offline_operation_id
  ) into created_attendance;

  return sale || jsonb_build_object(
    'attendance', to_jsonb(created_attendance),
    'already_checked_in', false
  );
end;
$$;

revoke all on function public.purchase_activity_card_and_check_in(
  uuid, uuid, text, text, uuid
) from public, anon;
grant execute on function public.purchase_activity_card_and_check_in(
  uuid, uuid, text, text, uuid
) to authenticated;
