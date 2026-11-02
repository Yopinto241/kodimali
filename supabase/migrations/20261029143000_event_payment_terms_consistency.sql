-- A delayed deposit must match the currently accepted quote and agreement.
-- A replacement cannot be confirmed by payment for superseded terms.
create or replace function public.finalize_platform_payment(p_order_id uuid,p_provider_transaction_id text,p_provider_payload jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare o public.platform_payment_orders; conflict_reason text; customer uuid;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'Service role required'; end if;
  select * into o from public.platform_payment_orders where id=p_order_id for update;
  if o.id is null then raise exception 'Payment order not found'; end if;
  if o.status in('paid','refunded') then return; end if;
  if o.purpose='event_balance' and exists(select 1 from public.event_plans where id=o.resource_id and status in('cancelled','disputed')) then conflict_reason:='Event was cancelled or is under review'; end if;
  if o.purpose='event_deposit' then
    begin
      perform 1 from public.event_plans where id=o.resource_id for update;
      if not exists(
        select 1 from public.event_plans p
        join public.event_quote_revisions q on q.id=p.accepted_quote_revision_id and q.status='accepted'
        join public.event_agreements a on a.plan_id=p.id and a.quote_revision_id=q.id and a.status='accepted'
        join public.payment_intents x on x.id=o.payment_intent_id
        where p.id=o.resource_id and x.customer_id=o.user_id and p.customer_id=o.user_id
          and x.metadata->>'quote_revision_id'=q.id::text
          and x.metadata->>'agreement_id'=a.id::text
          and round(q.total_tzs)::bigint=coalesce((x.metadata->>'agreed_total_minor')::bigint,-1)
      ) then raise exception 'The event quotation or agreement changed before payment was verified'; end if;
      if (select coalesce(sum(x.amount_minor),0) from public.payment_intents x where x.resource_type='event_plan' and x.resource_id=o.resource_id and x.status='verified_paid' and x.id is distinct from o.payment_intent_id)+round(o.amount_tzs)::bigint <
        (select split.deposit_minor from public.event_plans p join public.event_quote_revisions q on q.id=p.accepted_quote_revision_id cross join lateral public.calculate_booking_split(round(q.total_tzs)::bigint,25) split where p.id=o.resource_id) then raise exception 'The verified payment does not cover the accepted deposit'; end if;
      perform public.reserve_event_plan_inventory(o.resource_id,null,true);
    exception when others then
      get stacked diagnostics conflict_reason=message_text;
    end;
    if conflict_reason is not null then
      -- Verified money is recorded, but unavailable inventory is never promised.
      update public.event_equipment_allocations set status='expired' where plan_item_id in(select id from public.event_plan_items where plan_id=o.resource_id) and status='held';
      update public.event_service_bookings set status='expired' where plan_item_id in(select id from public.event_plan_items where plan_id=o.resource_id) and status='held';
      update public.event_plan_items set status='cancelled' where plan_id=o.resource_id and status in('provider_confirmed','customer_accepted');
    end if;
  end if;
  perform public.finalize_platform_payment_before_events_repair(p_order_id,p_provider_transaction_id,p_provider_payload);
  if conflict_reason is not null then
    update public.event_plans set status='disputed',updated_at=now() where id=o.resource_id returning customer_id into customer;
    update public.event_individual_bookings set status='disputed',payment_status='paid',updated_at=now() where plan_id=o.resource_id;
    update public.payment_intents set status='reconciliation_required',updated_at=now() where id=o.payment_intent_id;
    insert into public.financial_reconciliation_cases(provider,provider_transaction_id,provider_order_id,payment_intent_id,reported_amount_minor,currency,reason)
    values('sonicpesa',p_provider_transaction_id,o.provider_order_id,o.payment_intent_id,round(o.amount_tzs)::bigint,o.currency,'Event inventory unavailable after verified payment: '||conflict_reason);
    insert into public.event_emergency_escalations(plan_id,plan_item_id,reported_by,reason)
    select o.resource_id,id,customer,'Verified payment requires refund or replacement review: '||conflict_reason from public.event_plan_items where plan_id=o.resource_id and is_required;
    insert into public.notifications(user_id,type,title,body,payload) values(customer,'announcement','Event payment needs review','Your payment was received, but availability changed. KODIMALI will review a refund or a replacement with you.',jsonb_build_object('eventPlanId',o.resource_id,'route','account/events'));
  end if;
end $$;
