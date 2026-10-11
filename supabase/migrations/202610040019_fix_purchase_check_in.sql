-- Corrige « invalid input syntax for type uuid » : `select fonction() into
-- variable_composite` affectait le tuple complet au premier champ (uuid).
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
  created_attendance := public.check_in_member_with_payment(
    p_session_id,
    p_member_id,
    ((sale->'card')->>'id')::uuid,
    p_payment_method,
    p_offline_operation_id
  );

  return sale || jsonb_build_object(
    'attendance', to_jsonb(created_attendance),
    'already_checked_in', false
  );
end;
$$;
