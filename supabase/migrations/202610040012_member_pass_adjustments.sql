create table public.card_pass_adjustments (
  id uuid primary key default gen_random_uuid(),
  card_id uuid not null references public.cards (id) on delete cascade,
  adjusted_by uuid references public.profiles (id) on delete set null,
  previous_total_passes integer not null,
  new_total_passes integer not null,
  previous_remaining_passes integer not null,
  new_remaining_passes integer not null,
  reason text not null check (length(trim(reason)) > 0),
  adjusted_at timestamptz not null default now()
);

create index card_pass_adjustments_card_adjusted_at_idx
  on public.card_pass_adjustments (card_id, adjusted_at desc);

alter table public.card_pass_adjustments enable row level security;
grant select on public.card_pass_adjustments to authenticated;

create policy "Admins can read card pass adjustments"
  on public.card_pass_adjustments for select to authenticated
  using (public.has_app_role(array['admin']));

create or replace function public.adjust_member_card_passes(
  p_card_id uuid,
  p_remaining_passes integer,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_card public.cards;
  updated_card public.cards;
  adjusted_total integer;
begin
  if not public.has_app_role(array['admin']) then
    raise exception 'Only administrators can adjust class card passes'
      using errcode = '42501';
  end if;
  if p_card_id is null
    or p_remaining_passes is null
    or p_remaining_passes < 0
    or p_remaining_passes > 1000
    or coalesce(length(trim(p_reason)), 0) = 0
    or length(trim(p_reason)) > 500 then
    raise exception 'Invalid pass adjustment details'
      using errcode = '22023';
  end if;

  select * into existing_card
  from public.cards
  where id = p_card_id
  for update;
  if not found then
    raise exception 'Class card not found' using errcode = 'P0002';
  end if;

  adjusted_total := greatest(existing_card.total_passes, p_remaining_passes);
  update public.cards
  set total_passes = adjusted_total,
      remaining_passes = p_remaining_passes
  where id = p_card_id
  returning * into updated_card;

  insert into public.card_pass_adjustments (
    card_id,
    adjusted_by,
    previous_total_passes,
    new_total_passes,
    previous_remaining_passes,
    new_remaining_passes,
    reason
  )
  values (
    updated_card.id,
    auth.uid(),
    existing_card.total_passes,
    updated_card.total_passes,
    existing_card.remaining_passes,
    updated_card.remaining_passes,
    trim(p_reason)
  );

  return to_jsonb(updated_card);
end;
$$;

revoke all on function public.adjust_member_card_passes(uuid, integer, text)
  from public, anon;
grant execute on function public.adjust_member_card_passes(uuid, integer, text)
  to authenticated;
