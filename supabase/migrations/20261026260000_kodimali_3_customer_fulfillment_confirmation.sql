-- KODIMALI 3.0: independent customer fulfillment confirmation.
create or replace function public.confirm_customer_fulfillment_milestone(
  p_milestone_id uuid
)
returns public.fulfillment_milestones
language plpgsql
security definer
set search_path = public
as $$
declare
  v_milestone public.fulfillment_milestones;
  v_customer_id uuid;
begin
  select m
  into v_milestone
  from public.fulfillment_milestones m
  where m.id = p_milestone_id
  for update of m;

  if v_milestone.id is null then
    raise exception 'Fulfillment milestone not found';
  end if;

  select b.customer_id
  into v_customer_id
  from public.booking_requests b
  where b.id = v_milestone.booking_request_id;

  if v_customer_id is distinct from auth.uid() then
    raise exception 'Only the booking customer can confirm this milestone';
  end if;
  if v_milestone.status in ('verified','customer_confirmed') then
    return v_milestone;
  end if;
  if v_milestone.status in ('failed','disputed','waived') then
    raise exception 'This milestone cannot be customer-confirmed';
  end if;

  update public.fulfillment_milestones
  set status = 'customer_confirmed',
      customer_confirmed_at = coalesce(customer_confirmed_at, now()),
      updated_at = now()
  where id = p_milestone_id
  returning * into v_milestone;

  insert into public.audit_logs(actor_id, action, target_table, target_id, metadata)
  values(
    auth.uid(),
    'fulfillment_milestone_customer_confirmed',
    'fulfillment_milestones',
    p_milestone_id,
    jsonb_build_object(
      'booking_request_id', v_milestone.booking_request_id,
      'milestone_kind', v_milestone.milestone_kind
    )
  );
  return v_milestone;
end;
$$;

revoke all on function public.confirm_customer_fulfillment_milestone(uuid)
from public, anon, authenticated;
grant execute on function public.confirm_customer_fulfillment_milestone(uuid)
to authenticated, service_role;

comment on function public.confirm_customer_fulfillment_milestone(uuid) is
'Records the booking customer confirmation independently from provider confirmation and settlement release.';
