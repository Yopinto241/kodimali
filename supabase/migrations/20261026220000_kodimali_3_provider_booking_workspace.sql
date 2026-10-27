-- KODIMALI 3.0: provider booking workspace access and controlled fulfillment.
-- Providers may observe payment state for bookings assigned to them, but never
-- mutate payment intents, journals, postings or settlement records directly.

create policy payment_intents_assigned_provider_read
on public.payment_intents
for select
to authenticated
using (
  resource_type = 'booking_request'
  and resource_id is not null
  and public.is_booking_assigned_agent(resource_id)
);

create or replace function public.confirm_provider_fulfillment_milestone(
  p_milestone_id uuid
)
returns public.fulfillment_milestones
language plpgsql
security definer
set search_path = public
as $$
declare
  v_milestone public.fulfillment_milestones;
begin
  select *
  into v_milestone
  from public.fulfillment_milestones
  where id = p_milestone_id
  for update;

  if v_milestone.id is null then
    raise exception 'Fulfillment milestone not found';
  end if;

  if not (
    public.is_admin()
    or public.is_booking_assigned_agent(v_milestone.booking_request_id)
  ) then
    raise exception 'Only the assigned provider or an administrator can confirm this milestone';
  end if;

  if v_milestone.status in ('verified', 'failed', 'disputed', 'waived') then
    raise exception 'This milestone can no longer be provider-confirmed';
  end if;

  update public.fulfillment_milestones
  set status = 'provider_confirmed',
      provider_confirmed_at = coalesce(provider_confirmed_at, now()),
      updated_at = now()
  where id = p_milestone_id
  returning * into v_milestone;

  insert into public.audit_logs(actor_id, action, target_table, target_id, metadata)
  values (
    auth.uid(),
    'fulfillment_milestone_provider_confirmed',
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

revoke all on function public.confirm_provider_fulfillment_milestone(uuid)
from public, anon, authenticated;
grant execute on function public.confirm_provider_fulfillment_milestone(uuid)
to authenticated, service_role;

comment on function public.confirm_provider_fulfillment_milestone(uuid) is
'Records provider fulfillment confirmation with authorization and audit logging; it does not release settlement.';
