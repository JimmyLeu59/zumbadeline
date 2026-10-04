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
begin
  if not public.has_app_role(array['admin', 'assistant']) then
    raise exception 'Not authorized to check in members' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.members where id = p_member_id and is_active
  ) then
    raise exception 'Active member not found' using errcode = '23503';
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
    where id = p_card_id and member_id = p_member_id
    for update;
    if not found then
      raise exception 'Card does not belong to this member' using errcode = '23503';
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
      member_id, amount, payment_type, payment_method, paid_at,
      receipt_number, recorded_by, offline_operation_id
    )
    values (
      p_member_id, single_price, 'single_class', p_payment_method, now(),
      'ZUM-' || to_char(now() at time zone 'UTC', 'YYYYMMDD') || '-' ||
        upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
      (select auth.uid()), p_offline_operation_id
    );
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

revoke all on function public.check_in_member_with_payment(uuid, uuid, uuid, text, uuid)
  from public, anon;
grant execute on function public.check_in_member_with_payment(uuid, uuid, uuid, text, uuid)
  to authenticated;

do $$
begin
  if to_regprocedure('public.check_in_member(uuid,uuid,uuid,uuid)') is not null then
    execute 'revoke all on function public.check_in_member(uuid, uuid, uuid, uuid) from public, anon, authenticated';
  end if;
end;
$$;
