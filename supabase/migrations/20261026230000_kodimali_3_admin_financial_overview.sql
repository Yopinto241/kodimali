-- KODIMALI 3.0: permission-restricted, read-only financial control summary.

create or replace function public.get_admin_financial_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not (
    public.has_admin_permission('payments.view')
    or public.has_admin_permission('payments.manage')
    or public.has_admin_permission('refunds.manage')
  ) then
    raise exception 'Financial reporting permission required';
  end if;

  select jsonb_build_object(
    'verified_booking_collections_minor', coalesce((
      select sum(amount_minor) from public.payment_intents
      where product in ('booking_deposit','booking_balance')
        and status = 'verified_paid'
    ), 0),
    'verified_event_collections_minor', coalesce((
      select sum(amount_minor) from public.payment_intents
      where product in ('event_deposit','event_balance')
        and status = 'verified_paid'
    ), 0),
    'outstanding_booking_balances_minor', coalesce((
      select sum(t.balance_minor)
      from public.booking_terms_snapshots t
      where t.status = 'accepted'
        and not exists (
          select 1 from public.payment_intents p
          where p.resource_type = 'booking_request'
            and p.resource_id = t.booking_request_id
            and p.product = 'booking_balance'
            and p.status = 'verified_paid'
        )
    ), 0),
    'outstanding_event_balances_minor', coalesce((
      select sum(greatest(
        0,
        round(q.total_tzs)::bigint - coalesce((
          select sum(i.amount_minor) from public.payment_intents i
          where i.resource_type='event_plan'
            and i.resource_id=p.id
            and i.product in ('event_deposit','event_balance')
            and i.status='verified_paid'
        ),0)
      ))
      from public.event_plans p
      join public.event_quote_revisions q on q.id=p.accepted_quote_revision_id
      where q.status='accepted'
        and exists(select 1 from public.event_agreements a where a.plan_id=p.id and a.status='accepted')
        and p.status not in ('completed','cancelled')
    ), 0),
    'refund_liabilities_minor', coalesce((
      select sum(amount_minor) from public.refund_obligations
      where status in ('pending_review','approved','processing','reconciliation_required')
    ), 0),
    'refunded_minor', coalesce((
      select sum(amount_minor) from public.refund_obligations
      where status in ('refunded','partially_refunded')
    ), 0),
    'provider_payables_minor', coalesce((
      select sum(amount_minor) from public.provider_payables
      where status in ('pending_fulfillment','eligible','on_hold','scheduled')
    ), 0),
    'pending_settlements', coalesce((
      select count(*) from public.settlement_batches
      where status in ('draft','approved','processing','failed')
    ), 0),
    'contact_unlock_revenue_minor', coalesce((
      select sum(amount_minor) from public.payment_intents
      where product = 'contact_unlock' and status = 'verified_paid'
    ), 0),
    'paid_chat_revenue_minor', coalesce((
      select sum(amount_minor) from public.payment_intents
      where product = 'paid_chat_unlock' and status = 'verified_paid'
    ), 0),
    'booking_service_fee_revenue_minor', coalesce((
      select sum(amount_minor) from public.payment_intents
      where product = 'booking_service_fee' and status = 'verified_paid'
    ), 0),
    'commission_obligations_minor', coalesce((
      select sum(amount_minor) from public.commission_obligations
      where kind = 'agent_commission' and status in ('pending','eligible','payable','disputed')
    ), 0),
    'referral_reward_obligations_minor', coalesce((
      select sum(amount_minor) from public.commission_obligations
      where kind = 'referral_reward' and status in ('pending','eligible','payable','disputed')
    ), 0),
    'verified_external_deal_value_minor', coalesce((
      select sum(claimed_value_minor) from public.external_deal_declarations
      where status in ('verified','commission_assessed','settled')
    ), 0),
    'open_reconciliation_cases', coalesce((
      select count(*) from public.financial_reconciliation_cases
      where status in ('open','investigating')
    ), 0),
    'disputed_provider_payables_minor', coalesce((
      select sum(amount_minor) from public.provider_payables
      where status = 'disputed'
    ), 0),
    'generated_at', now()
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_admin_financial_overview()
from public, anon, authenticated;
grant execute on function public.get_admin_financial_overview()
to authenticated, service_role;

comment on function public.get_admin_financial_overview() is
'Read-only financial control summary. Booking collections, liabilities, platform revenue and external values remain separate.';
