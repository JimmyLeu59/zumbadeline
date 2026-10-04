create or replace function public.record_payment(
  p_member_id uuid,
  p_payment_type text,
  p_payment_method text,
  p_amount numeric,
  p_notes text default null,
  p_offline_operation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_payment public.payments;
  configured_amount numeric(10, 2);
begin
  if not public.has_app_role(array['admin', 'assistant']) then
    raise exception 'Not authorized to record payments' using errcode = '42501';
  end if;
  if p_payment_type not in ('membership', 'single_class', 'class_card', 'event', 'other')
    or p_payment_method not in ('cash', 'cheque', 'bank_transfer', 'card')
    or p_amount < 0 then
    raise exception 'Invalid payment details' using errcode = '22023';
  end if;
  if p_payment_type = 'class_card' then
    raise exception 'Class cards must be sold through purchase_class_card'
      using errcode = '22023';
  end if;
  if p_payment_type in ('membership', 'single_class') then
    select case
      when p_payment_type = 'membership' then annual_membership_fee
      else single_class_price
    end
    into configured_amount
    from public.pricing_settings
    where id = 1;
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
    if found then return to_jsonb(created_payment); end if;
  end if;

  insert into public.payments (
    member_id, amount, payment_type, payment_method, paid_at,
    receipt_number, notes, recorded_by, offline_operation_id
  )
  values (
    p_member_id, p_amount, p_payment_type, p_payment_method, now(),
    'ZUM-' || to_char(now() at time zone 'UTC', 'YYYYMMDD') || '-' ||
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    p_notes, (select auth.uid()), p_offline_operation_id
  )
  returning * into created_payment;

  if p_payment_type = 'membership' then
    update public.members
    set membership_valid_until =
      greatest(coalesce(membership_valid_until, current_date), current_date) + interval '1 year'
    where id = p_member_id;
  end if;

  return to_jsonb(created_payment);
end;
$$;

create or replace function public.purchase_class_card(
  p_member_id uuid,
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
  if not public.has_app_role(array['admin', 'assistant']) then
    raise exception 'Not authorized to sell class cards' using errcode = '42501';
  end if;
  if p_payment_method not in ('cash', 'cheque', 'bank_transfer', 'card') then
    raise exception 'Invalid payment method' using errcode = '22023';
  end if;

  if p_offline_operation_id is not null then
    select * into created_payment
    from public.payments
    where offline_operation_id = p_offline_operation_id;
    if found then
      select * into created_card from public.cards where id = created_payment.card_id;
      return jsonb_build_object(
        'payment', to_jsonb(created_payment),
        'card', to_jsonb(created_card)
      );
    end if;
  end if;

  perform 1
  from public.members
  where id = p_member_id and is_active
  for update;
  if not found then
    raise exception 'Active member not found' using errcode = '23503';
  end if;

  select count(*) into purchase_count
  from public.cards where member_id = p_member_id;
  select card_pass_count,
         case when purchase_count = 0 then first_card_price else renewal_card_price end
  into pass_count, purchase_price
  from public.pricing_settings where id = 1;
  if not found then
    raise exception 'Pricing settings are not configured' using errcode = 'P0002';
  end if;

  insert into public.cards (
    member_id, purchase_number, total_passes, remaining_passes, purchase_price
  )
  values (
    p_member_id, purchase_count + 1, pass_count, pass_count, purchase_price
  )
  returning * into created_card;

  insert into public.payments (
    member_id, card_id, amount, payment_type, payment_method, paid_at,
    receipt_number, recorded_by, offline_operation_id
  )
  values (
    p_member_id, created_card.id, purchase_price, 'class_card', p_payment_method,
    now(),
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

revoke all on function public.record_payment(uuid, text, text, numeric, text, uuid)
  from public, anon;
revoke all on function public.purchase_class_card(uuid, text, uuid)
  from public, anon;
grant execute on function public.record_payment(uuid, text, text, numeric, text, uuid)
  to authenticated;
grant execute on function public.purchase_class_card(uuid, text, uuid)
  to authenticated;
