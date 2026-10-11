create table public.subscription_plans (
  code text primary key,
  label text not null,
  period text not null check (period in ('month', 'quarter')),
  weekly_limit smallint not null check (weekly_limit between 1 and 7),
  price numeric(10, 2) not null check (price >= 0),
  is_active boolean not null default true,
  unique (period, weekly_limit)
);

insert into public.subscription_plans (code, label, period, weekly_limit, price)
values
  ('monthly_1', 'Forfait mensuel · 1 cours/semaine', 'month', 1, 20),
  ('monthly_2', 'Forfait mensuel · 2 cours/semaine', 'month', 2, 35),
  ('monthly_3', 'Forfait mensuel · 3 cours/semaine', 'month', 3, 48),
  ('monthly_4', 'Forfait mensuel · 4 cours/semaine', 'month', 4, 57),
  ('quarterly_1', 'Forfait trimestriel · 1 cours/semaine', 'quarter', 1, 53),
  ('quarterly_2', 'Forfait trimestriel · 2 cours/semaine', 'quarter', 2, 95),
  ('quarterly_3', 'Forfait trimestriel · 3 cours/semaine', 'quarter', 3, 128),
  ('quarterly_4', 'Forfait trimestriel · 4 cours/semaine', 'quarter', 4, 154);

alter table public.subscription_plans enable row level security;
create policy "Authenticated users can read plans"
  on public.subscription_plans for select to authenticated
  using (true);
create policy "Admins can manage plans"
  on public.subscription_plans for all to authenticated
  using (public.has_app_role(array['admin']))
  with check (public.has_app_role(array['admin']));

alter table public.cards
  add column plan_code text references public.subscription_plans (code),
  add column weekly_limit smallint check (weekly_limit is null or weekly_limit > 0),
  add column expires_at timestamptz;

-- Les 10 cours restent sans date limite : plan_code, weekly_limit et
-- expires_at ne sont renseignés que pour les forfaits mensuels/trimestriels.

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
  card_weekly_limit smallint;
  card_expires_at timestamptz;
  week_usage integer;
  single_price numeric(10, 2);
  session_activity_id uuid;
  session_starts_at timestamptz;
begin
  select activity_id, starts_at into session_activity_id, session_starts_at
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
    select remaining_passes, weekly_limit, expires_at
    into card_remaining, card_weekly_limit, card_expires_at
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
    if card_expires_at is not null and session_starts_at > card_expires_at then
      raise exception 'Card has expired' using errcode = '23514';
    end if;
    if card_weekly_limit is not null then
      select count(*) into week_usage
      from public.attendances a
      join public.sessions s on s.id = a.session_id
      where a.card_id = p_card_id
        and date_trunc('week', s.starts_at at time zone 'Europe/Paris')
          = date_trunc('week', session_starts_at at time zone 'Europe/Paris');
      if week_usage >= card_weekly_limit then
        raise exception 'Weekly class limit reached for this card'
          using errcode = '23514';
      end if;
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

drop function public.purchase_activity_card_and_check_in(uuid, uuid, text, text, uuid);
drop function public.purchase_activity_card(uuid, uuid, text, text, uuid);

create or replace function public.purchase_activity_card(
  p_member_id uuid,
  p_activity_id uuid,
  p_price_tier text,
  p_payment_method text,
  p_offline_operation_id uuid default null,
  p_plan_code text default null
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
  plan public.subscription_plans;
  plan_code_value text;
  plan_weekly_limit smallint;
  plan_label text;
  card_expires_at timestamptz;
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

  if p_plan_code is not null then
    select * into plan
    from public.subscription_plans
    where code = p_plan_code and is_active;
    if not found then
      raise exception 'Unknown or inactive plan' using errcode = '22023';
    end if;
    purchase_price := plan.price;
    plan_code_value := plan.code;
    plan_weekly_limit := plan.weekly_limit;
    plan_label := plan.label;
    -- Plafond théorique : semaines civiles couvertes par la période.
    pass_count := plan.weekly_limit * case plan.period when 'month' then 5 else 14 end;
    card_expires_at := case plan.period
      when 'month' then now() + interval '30 days'
      else now() + interval '3 months'
    end;
  else
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
  end if;

  insert into public.cards (
    member_id, activity_id, purchase_number, total_passes, remaining_passes,
    purchase_price, price_tier, plan_code, weekly_limit, expires_at
  )
  values (
    p_member_id, p_activity_id, purchase_count + 1, pass_count, pass_count,
    purchase_price, p_price_tier, plan_code_value, plan_weekly_limit,
    card_expires_at
  )
  returning * into created_card;

  insert into public.payments (
    member_id, activity_id, card_id, amount, payment_type, payment_method,
    paid_at, receipt_number, notes, recorded_by, offline_operation_id
  )
  values (
    p_member_id, p_activity_id, created_card.id, purchase_price, 'class_card',
    p_payment_method, now(),
    'ZUM-' || to_char(now() at time zone 'UTC', 'YYYYMMDD') || '-' ||
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    plan_label, (select auth.uid()), p_offline_operation_id
  )
  returning * into created_payment;

  return jsonb_build_object(
    'payment', to_jsonb(created_payment),
    'card', to_jsonb(created_card)
  );
end;
$$;

revoke all on function public.purchase_activity_card(
  uuid, uuid, text, text, uuid, text
) from public, anon;
grant execute on function public.purchase_activity_card(
  uuid, uuid, text, text, uuid, text
) to authenticated;

create or replace function public.purchase_activity_card_and_check_in(
  p_session_id uuid,
  p_member_id uuid,
  p_price_tier text,
  p_payment_method text,
  p_offline_operation_id uuid,
  p_plan_code text default null
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
    p_offline_operation_id,
    p_plan_code
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
  uuid, uuid, text, text, uuid, text
) from public, anon;
grant execute on function public.purchase_activity_card_and_check_in(
  uuid, uuid, text, text, uuid, text
) to authenticated;
