drop policy if exists "Staff can manage sessions" on public.sessions;

create policy "Staff can create sessions"
  on public.sessions for insert to authenticated
  with check (public.has_app_role(array['admin', 'assistant']));

create policy "Staff can update sessions"
  on public.sessions for update to authenticated
  using (public.has_app_role(array['admin', 'assistant']))
  with check (public.has_app_role(array['admin', 'assistant']));

create or replace function public.delete_event(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_app_role(array['admin']) then
    raise exception 'Only administrators can delete events'
      using errcode = '42501';
  end if;

  delete from public.sessions
  where id = p_event_id and session_type = 'event';

  if not found then
    raise exception 'Event not found' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.delete_payment(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_payment public.payments;
  associated_card public.cards;
  card_exists boolean;
begin
  if not public.has_app_role(array['admin']) then
    raise exception 'Only administrators can delete payments'
      using errcode = '42501';
  end if;

  select * into existing_payment
  from public.payments
  where id = p_payment_id
  for update;
  if not found then
    raise exception 'Payment not found' using errcode = 'P0002';
  end if;

  if existing_payment.card_id is not null then
    select * into associated_card
    from public.cards
    where id = existing_payment.card_id
    for update;
    card_exists := found;

    if card_exists then
      if associated_card.remaining_passes <> associated_card.total_passes
        or exists (
          select 1
          from public.attendances
          where card_id = associated_card.id
        ) then
        raise exception 'The card has already been used and cannot be deleted'
          using errcode = '23514';
      end if;
      delete from public.payments where id = p_payment_id;
      delete from public.cards where id = associated_card.id;
      return;
    end if;
  end if;

  delete from public.payments where id = p_payment_id;
end;
$$;

revoke all on function public.delete_event(uuid) from public, anon;
revoke all on function public.delete_payment(uuid) from public, anon;
grant execute on function public.delete_event(uuid) to authenticated;
grant execute on function public.delete_payment(uuid) to authenticated;
