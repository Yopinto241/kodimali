-- Explicit cancellation, replacement consent, and coordinator resolution.
alter table public.event_substitution_proposals add column accepted_plan_item_id uuid references public.event_plan_items(id);

create function public.cancel_customer_event(p_plan_id uuid,p_reason text)
returns public.event_cancellations language plpgsql security definer set search_path=public as $$
declare p public.event_plans; r public.event_cancellations;
begin
  select * into p from public.event_plans where id=p_plan_id and customer_id=auth.uid() for update;
  if p.id is null or p.status in('completed','cancelled') or nullif(trim(p_reason),'') is null then raise exception 'Active event and cancellation reason required'; end if;
  insert into public.event_cancellations(plan_id,requested_by,party,reason,status) values(p.id,auth.uid(),'customer',trim(p_reason),'reviewing') returning * into r;
  update public.event_plans set status='cancelled',updated_at=now() where id=p.id;
  update public.event_plan_items set status='cancelled' where plan_id=p.id;
  update public.event_equipment_allocations set status='cancelled' where plan_item_id in(select id from public.event_plan_items where plan_id=p.id) and status in('held','confirmed');
  update public.event_service_bookings set status='cancelled' where plan_item_id in(select id from public.event_plan_items where plan_id=p.id) and status in('held','confirmed','pending');
  update public.event_individual_bookings set status='cancelled',updated_at=now() where plan_id=p.id;
  update public.event_quote_revisions set status='superseded' where plan_id=p.id and status in('sent','draft');
  update public.event_agreements set status='cancelled' where plan_id=p.id and status in('sent','draft');
  insert into public.event_emergency_escalations(plan_id,reported_by,reason) values(p.id,auth.uid(),'Customer cancellation; review any paid amounts: '||trim(p_reason));
  insert into public.event_audit_log(plan_id,actor_id,action,details) values(p.id,auth.uid(),'customer.cancelled',jsonb_build_object('reason',p_reason,'refund_requires_review',true));
  return r;
end $$;

create or replace function public.provider_cancel_event_item(p_plan_item_id uuid,p_reason text)
returns public.event_cancellations language plpgsql security definer set search_path=public as $$
declare i public.event_plan_items; p public.event_plans; r public.event_cancellations;
begin
  select * into i from public.event_plan_items where id=p_plan_item_id;
  select * into p from public.event_plans where id=i.plan_id for update;
  if i.id is null or i.status in('cancelled','completed','provider_declined') or p.status in('completed','cancelled') or nullif(trim(p_reason),'') is null then raise exception 'Active request and cancellation reason required'; end if;
  if not (
    exists(select 1 from public.event_equipment_items where id=i.equipment_id and owner_id=public.current_owner_id())
    or exists(select 1 from public.event_service_offerings o join public.event_service_profiles s on s.id=o.provider_id where o.id=i.offering_id and s.profile_id=auth.uid())
  ) then raise exception 'Provider access required'; end if;
  update public.event_plan_items set status='cancelled' where id=i.id;
  update public.event_equipment_allocations set status='cancelled' where plan_item_id=i.id and status in('held','confirmed');
  update public.event_service_bookings set status='cancelled' where plan_item_id=i.id and status in('pending','held','confirmed');
  update public.event_plans set status='partially_confirmed',updated_at=now() where id=p.id;
  update public.event_individual_bookings set status='cancelled',updated_at=now() where plan_id=p.id;
  insert into public.event_cancellations(plan_id,plan_item_id,requested_by,party,reason,status) values(p.id,i.id,auth.uid(),'provider',trim(p_reason),'reviewing') returning * into r;
  insert into public.event_emergency_escalations(plan_id,plan_item_id,reported_by,reason) values(p.id,i.id,auth.uid(),'Provider cancellation: '||trim(p_reason));
  insert into public.notifications(user_id,type,title,body,payload) values(p.customer_id,'announcement','Event supplier cancelled','Your supplier cancelled. KODIMALI will review a replacement or refund with you.',jsonb_build_object('eventPlanId',p.id,'route','account/events'));
  insert into public.event_audit_log(plan_id,actor_id,action,details) values(p.id,auth.uid(),'provider.cancelled',jsonb_build_object('item_id',i.id,'reason',p_reason));
  return r;
end $$;

create function public.propose_event_replacement(p_item_id uuid,p_replacement_id uuid,p_reason text,p_price_change_tzs numeric default 0)
returns public.event_substitution_proposals language plpgsql security definer set search_path=public as $$
declare i public.event_plan_items; p public.event_plans; r public.event_substitution_proposals;
begin
  if not public.has_admin_permission('events.manage') then raise exception 'Event coordinator permission required'; end if;
  select * into i from public.event_plan_items where id=p_item_id;
  select * into p from public.event_plans where id=i.plan_id for update;
  if p.id is null or i.status not in('cancelled','provider_declined') or p.status in('cancelled','completed') or nullif(trim(p_reason),'') is null then raise exception 'Cancelled supplier and replacement reason required'; end if;
  if i.item_kind='equipment' then
    if not exists(select 1 from public.event_equipment_items where id=p_replacement_id and is_active and verification_status='verified' and publication_status='published' and total_quantity>=i.requested_quantity) then raise exception 'Published replacement equipment required'; end if;
  else
    if not exists(select 1 from public.event_service_offerings o join public.event_service_profiles s on s.id=o.provider_id where o.id=p_replacement_id and o.is_active and o.publication_status='published' and s.is_active and s.verification_status='verified') then raise exception 'Published replacement service required'; end if;
  end if;
  if p_replacement_id in (i.equipment_id,i.offering_id) then raise exception 'Choose a different supplier'; end if;
  update public.event_substitution_proposals set status='expired' where replaces_plan_item_id=i.id and status='proposed';
  insert into public.event_substitution_proposals(plan_id,replaces_plan_item_id,proposed_equipment_id,proposed_offering_id,reason,price_change_tzs,proposed_by,expires_at)
  values(p.id,i.id,case when i.item_kind='equipment' then p_replacement_id end,case when i.item_kind='service' then p_replacement_id end,trim(p_reason),coalesce(p_price_change_tzs,0),auth.uid(),least(now()+interval '24 hours',lower(p.event_period))) returning * into r;
  insert into public.notifications(user_id,type,title,body,payload) values(p.customer_id,'announcement','Review an event replacement','Review the proposed supplier and price change. Your approval requests the replacement; its provider must still confirm.',jsonb_build_object('eventPlanId',p.id,'route','account/events'));
  insert into public.event_audit_log(plan_id,actor_id,action,details) values(p.id,auth.uid(),'replacement.proposed',to_jsonb(r));
  return r;
end $$;

create function public.respond_event_replacement(p_proposal_id uuid,p_accept boolean)
returns public.event_substitution_proposals language plpgsql security definer set search_path=public as $$
declare r public.event_substitution_proposals; p public.event_plans; i public.event_plan_items; replacement public.event_plan_items;
begin
  select * into r from public.event_substitution_proposals where id=p_proposal_id;
  select * into p from public.event_plans where id=r.plan_id and customer_id=auth.uid() for update;
  select * into r from public.event_substitution_proposals where id=p_proposal_id for update;
  if p.id is null or r.status<>'proposed' or r.expires_at<=now() or p.status in('cancelled','completed') then raise exception 'Replacement is unavailable or expired'; end if;
  if p_accept then
    select * into i from public.event_plan_items where id=r.replaces_plan_item_id;
    if i.status not in('cancelled','provider_declined') then raise exception 'Original request is not cancelled'; end if;
    update public.event_plan_items set is_required=false where id=i.id;
    insert into public.event_plan_items(plan_id,item_kind,equipment_id,offering_id,requested_quantity,is_required,requirements)
    values(p.id,i.item_kind,r.proposed_equipment_id,r.proposed_offering_id,i.requested_quantity,true,'Customer accepted replacement proposal '||r.id::text||'; provider confirmation and revised quote required') returning * into replacement;
    -- Previous consent cannot authorize a new supplier or new charge.
    update public.event_quote_revisions set status='superseded' where plan_id=p.id and status in('draft','sent','accepted');
    update public.event_agreements set status='superseded' where plan_id=p.id and status in('draft','sent','accepted');
    update public.event_plans set status='provider_review',accepted_quote_revision_id=null,required_component_count=(select count(*) from public.event_plan_items where plan_id=p.id and is_required),updated_at=now() where id=p.id;
    update public.event_individual_bookings set plan_item_id=replacement.id,status='requested',provider_response=null,provider_responded_at=null,updated_at=now() where plan_id=p.id;
  end if;
  update public.event_substitution_proposals set status=case when p_accept then 'accepted' else 'rejected' end,decided_at=now(),accepted_plan_item_id=replacement.id where id=r.id returning * into r;
  insert into public.event_audit_log(plan_id,actor_id,action,details) values(p.id,auth.uid(),case when p_accept then 'replacement.accepted' else 'replacement.rejected' end,to_jsonb(r));
  return r;
end $$;

create function public.resolve_event_escalation(p_escalation_id uuid,p_resolution text)
returns void language plpgsql security definer set search_path=public as $$
declare e public.event_emergency_escalations; p public.event_plans;
begin
  if not public.has_admin_permission('events.escalations') then raise exception 'Event escalation permission required'; end if;
  select * into e from public.event_emergency_escalations where id=p_escalation_id;
  select * into p from public.event_plans where id=e.plan_id for update;
  if p.id is null or p.status not in('confirmed','completed','cancelled') or nullif(trim(p_resolution),'') is null then raise exception 'Confirm a replacement or cancel the event before resolution'; end if;
  if exists(select 1 from public.financial_reconciliation_cases c join public.payment_intents x on x.id=c.payment_intent_id where x.resource_type='event_plan' and x.resource_id=p.id and c.status in('open','investigating')) then raise exception 'Finance must resolve the payment review first'; end if;
  if p.status='cancelled' and (select coalesce(sum(amount_tzs),0) from public.event_payment_obligations where plan_id=p.id and kind in('deposit','balance') and status='paid')>(select coalesce(sum(amount_tzs),0) from public.event_payment_obligations where plan_id=p.id and kind='refund' and status='refunded') and not exists(select 1 from public.event_cancellations where plan_id=p.id and status='completed' and resolution is not null) then raise exception 'Finance must record the cancellation settlement first'; end if;
  update public.event_emergency_escalations set status='resolved',assigned_admin_id=auth.uid(),resolved_at=now() where id=e.id;
  update public.event_cancellations set status='completed',resolution=p_resolution,resolved_by=auth.uid(),resolved_at=now() where plan_id=p.id and status in('submitted','reviewing') and (p.status='cancelled' or plan_item_id=e.plan_item_id);
  insert into public.event_audit_log(plan_id,actor_id,action,details) values(p.id,auth.uid(),'escalation.resolved',jsonb_build_object('escalation_id',e.id,'resolution',p_resolution));
end $$;

revoke all on function public.cancel_customer_event(uuid,text),public.propose_event_replacement(uuid,uuid,text,numeric),public.respond_event_replacement(uuid,boolean),public.resolve_event_escalation(uuid,text) from public,anon;
grant execute on function public.cancel_customer_event(uuid,text),public.propose_event_replacement(uuid,uuid,text,numeric),public.respond_event_replacement(uuid,boolean),public.resolve_event_escalation(uuid,text) to authenticated;

-- Mobile keeps an editable draft while selecting components. Submitting that
-- draft must commit every component together and be safe to retry.
create function public.submit_event_draft(p_plan_id uuid,p_items jsonb)
returns public.event_plans language plpgsql security definer set search_path=public as $$
declare p public.event_plans; saved public.event_plan_submissions; entry jsonb; payload jsonb;
begin
  select * into p from public.event_plans where id=p_plan_id and customer_id=auth.uid() for update;
  if p.id is null then raise exception 'Your event draft was not found'; end if;
  payload:=jsonb_build_object('items',p_items);
  select * into saved from public.event_plan_submissions where customer_id=auth.uid() and idempotency_key='draft:'||p.id::text;
  if saved.plan_id is not null then
    if saved.request_payload<>payload then raise exception 'This plan was already submitted with different components'; end if;
    return p;
  end if;
  if p.status<>'draft' or lower(p.event_period)<=now() then raise exception 'Editable future draft required'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>100 then raise exception 'Select between one and 100 components'; end if;
  delete from public.event_plan_items where plan_id=p.id;
  for entry in select value from jsonb_array_elements(p_items) loop
    if entry->>'kind'='equipment' then
      if not exists(select 1 from public.event_equipment_items where id=(entry->>'id')::uuid and verification_status='verified' and publication_status='published' and is_active and total_quantity>=(entry->>'quantity')::integer) then raise exception 'Selected equipment is unavailable'; end if;
      perform public.add_event_plan_item(p.id,'equipment',(entry->>'id')::uuid,null,(entry->>'quantity')::integer,true,null);
    elsif entry->>'kind'='service' then
      if not exists(select 1 from public.event_service_offerings o join public.event_service_profiles s on s.id=o.provider_id where o.id=(entry->>'id')::uuid and o.is_active and o.publication_status='published' and s.is_active and s.verification_status='verified') then raise exception 'Selected professional is unavailable'; end if;
      perform public.add_event_plan_item(p.id,'service',null,(entry->>'id')::uuid,null,true,null);
    else raise exception 'Invalid component'; end if;
  end loop;
  p:=public.request_event_quote(p.id);
  insert into public.event_plan_submissions(customer_id,idempotency_key,request_payload,plan_id) values(auth.uid(),'draft:'||p.id::text,payload,p.id);
  return p;
end $$;
revoke all on function public.submit_event_draft(uuid,jsonb) from public,anon;
grant execute on function public.submit_event_draft(uuid,jsonb) to authenticated;

-- Records an externally completed settlement. This never initiates a transfer.
create table public.event_cancellation_settlements(
  cancellation_id uuid primary key references public.event_cancellations(id),
  transaction_reference text not null unique,refund_amount_tzs numeric(14,2) not null check(refund_amount_tzs>=0),
  recorded_by uuid not null references public.profiles(id),recorded_at timestamptz not null default now()
);
alter table public.event_cancellation_settlements enable row level security;
create policy event_settlements_read on public.event_cancellation_settlements for select to authenticated using(
  public.has_admin_permission('payments.manage') or exists(select 1 from public.event_cancellations c join public.event_plans p on p.id=c.plan_id where c.id=cancellation_id and p.customer_id=auth.uid())
);
create function public.record_event_cancellation_settlement(p_cancellation_id uuid,p_transaction_reference text,p_refund_amount_tzs numeric)
returns void language plpgsql security definer set search_path=public as $$
declare c public.event_cancellations; p public.event_plans; paid numeric; refunded numeric; j uuid; cash uuid; liability uuid;
begin
  if not public.has_admin_permission('payments.manage') then raise exception 'Finance permission required'; end if;
  select * into c from public.event_cancellations where id=p_cancellation_id;
  select * into p from public.event_plans where id=c.plan_id for update;
  if p.id is null or c.status not in('submitted','reviewing','approved') or nullif(trim(p_transaction_reference),'') is null or p_refund_amount_tzs is null or p_refund_amount_tzs<0 then raise exception 'Open cancellation, settlement reference and non-negative refund required'; end if;
  select coalesce(sum(amount_tzs),0) into paid from public.event_payment_obligations where plan_id=p.id and kind in('deposit','balance') and status='paid';
  select coalesce(sum(amount_tzs),0) into refunded from public.event_payment_obligations where plan_id=p.id and kind='refund' and status='refunded';
  if p_refund_amount_tzs>paid-refunded then raise exception 'Refund exceeds remaining collected amount'; end if;
  insert into public.event_cancellation_settlements(cancellation_id,transaction_reference,refund_amount_tzs,recorded_by) values(c.id,trim(p_transaction_reference),p_refund_amount_tzs,auth.uid());
  update public.event_cancellations set status='completed',refundable_amount_tzs=p_refund_amount_tzs,resolution='External settlement: '||trim(p_transaction_reference),resolved_by=auth.uid(),resolved_at=now() where id=c.id;
  if p_refund_amount_tzs>0 then
    insert into public.event_payment_obligations(plan_id,kind,amount_tzs,status,collection_enabled,external_reference) values(p.id,'refund',p_refund_amount_tzs,'refunded',false,trim(p_transaction_reference));
    select id into cash from public.financial_accounts where code='CASH_PROVIDER_CLEARING';
    select id into liability from public.financial_accounts where code='BOOKING_COLLECTIONS_LIABILITY';
    insert into public.financial_journals(journal_type,reference_type,reference_id,idempotency_key,description,posted_by,metadata)
    values('payment_refund','event_cancellation',c.id,'event-cancellation-refund:'||c.id::text,'Externally completed cancellation refund',auth.uid(),jsonb_build_object('reference',p_transaction_reference)) returning id into j;
    insert into public.financial_postings(journal_id,account_id,debit_minor,memo) values(j,liability,round(p_refund_amount_tzs)::bigint,'Event funds returned');
    insert into public.financial_postings(journal_id,account_id,credit_minor,memo) values(j,cash,round(p_refund_amount_tzs)::bigint,'Externally completed cancellation refund');
  end if;
  insert into public.event_audit_log(plan_id,actor_id,action,details) values(p.id,auth.uid(),'cancellation.settlement_recorded',jsonb_build_object('cancellation_id',c.id,'reference',p_transaction_reference,'refund_amount_tzs',p_refund_amount_tzs));
  insert into public.notifications(user_id,type,title,body,payload) values(p.customer_id,'announcement','Event cancellation review completed','Your cancellation settlement has been recorded. See the event cancellation details for the reference.',jsonb_build_object('eventPlanId',p.id,'route','account/events'));
end $$;
revoke all on function public.record_event_cancellation_settlement(uuid,text,numeric) from public,anon;
grant execute on function public.record_event_cancellation_settlement(uuid,text,numeric) to authenticated;

create function public.resolve_event_payment_review(p_case_id uuid,p_decision text,p_reference text)
returns void language plpgsql security definer set search_path=public as $$
declare c public.financial_reconciliation_cases; x public.payment_intents; p public.event_plans; j uuid; cash uuid; liability uuid;
begin
  if not public.has_admin_permission('payments.manage') then raise exception 'Finance permission required'; end if;
  select * into c from public.financial_reconciliation_cases where id=p_case_id;
  select * into x from public.payment_intents where id=c.payment_intent_id;
  select * into p from public.event_plans where id=x.resource_id and x.resource_type='event_plan' for update;
  if p.id is null or c.status not in('open','investigating') or x.status<>'reconciliation_required' or nullif(trim(p_reference),'') is null then raise exception 'Unresolved event payment and review reference required'; end if;
  if p_decision='credit_for_replacement' then
    if not exists(select 1 from public.event_substitution_proposals where plan_id=p.id and status='accepted') or p.status in('cancelled','completed') then raise exception 'Customer must accept a replacement before retaining payment as credit'; end if;
    update public.payment_intents set status='verified_paid',updated_at=now() where id=x.id;
  elsif p_decision='refund_recorded' then
    -- Full refund was already sent externally. Record a balanced reversal.
    select id into cash from public.financial_accounts where code='CASH_PROVIDER_CLEARING';
    select id into liability from public.financial_accounts where code='BOOKING_COLLECTIONS_LIABILITY';
    insert into public.financial_journals(journal_type,reference_type,reference_id,idempotency_key,description,posted_by,metadata)
    values('payment_refund','payment_intent',x.id,'event-review-refund:'||x.id::text,'Externally completed event refund',auth.uid(),jsonb_build_object('reference',p_reference)) returning id into j;
    insert into public.financial_postings(journal_id,account_id,debit_minor,memo) values(j,liability,x.amount_minor,'Event funds returned');
    insert into public.financial_postings(journal_id,account_id,credit_minor,memo) values(j,cash,x.amount_minor,'Externally completed refund');
    update public.payment_intents set status='refunded',updated_at=now() where id=x.id;
    update public.platform_payment_orders set status='refunded',updated_at=now() where payment_intent_id=x.id;
    insert into public.event_payment_obligations(plan_id,kind,amount_tzs,status,collection_enabled,external_reference) values(p.id,'refund',x.amount_minor,'refunded',false,trim(p_reference));
    update public.event_plans set status='cancelled',updated_at=now() where id=p.id;
    update public.event_plan_items set status='cancelled' where plan_id=p.id;
    update public.event_equipment_allocations set status='cancelled' where plan_item_id in(select id from public.event_plan_items where plan_id=p.id) and status in('held','confirmed');
    update public.event_service_bookings set status='cancelled' where plan_item_id in(select id from public.event_plan_items where plan_id=p.id) and status in('held','confirmed','pending');
    update public.event_individual_bookings set status='cancelled',payment_status='refunded',updated_at=now() where plan_id=p.id;
  else raise exception 'Choose completed refund or customer-approved replacement credit'; end if;
  update public.financial_reconciliation_cases set status='resolved',resolution=p_decision||': '||trim(p_reference),resolved_by=auth.uid(),resolved_at=now() where id=c.id;
  insert into public.event_audit_log(plan_id,actor_id,action,details) values(p.id,auth.uid(),'payment.review_resolved',jsonb_build_object('case_id',c.id,'decision',p_decision,'reference',p_reference));
  insert into public.notifications(user_id,type,title,body,payload) values(p.customer_id,'announcement','Event payment review completed',case when p_decision='refund_recorded' then 'Your externally completed refund has been recorded.' else 'Your earlier payment is retained as credit for the replacement you accepted. Review the revised quote and agreement.' end,jsonb_build_object('eventPlanId',p.id,'route','account/events'));
end $$;
revoke all on function public.resolve_event_payment_review(uuid,text,text) from public,anon;
grant execute on function public.resolve_event_payment_review(uuid,text,text) to authenticated;
