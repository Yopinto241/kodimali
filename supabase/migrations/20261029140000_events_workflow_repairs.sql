-- Events approval, inventory, idempotency, payment and media boundaries.

-- Participant policies previously queried plans -> items -> plans recursively.
create function public.can_read_event_plan(p_plan_id uuid,p_item_id uuid default null)
returns boolean language sql stable security definer set search_path=public as $$
  select auth.uid() is not null and (
    public.has_admin_permission('events.manage')
    or exists(select 1 from public.event_plans where id=p_plan_id and customer_id=auth.uid())
    or exists(select 1 from public.event_plan_items i
      left join public.event_equipment_items e on e.id=i.equipment_id
      left join public.owner_profiles owner on owner.id=e.owner_id
      left join public.event_service_offerings o on o.id=i.offering_id
      left join public.event_service_profiles s on s.id=o.provider_id
      where i.plan_id=p_plan_id and (p_item_id is null or i.id=p_item_id)
      and (owner.profile_id=auth.uid() or s.profile_id=auth.uid()))
  );
$$;
revoke all on function public.can_read_event_plan(uuid,uuid) from public,anon;
grant execute on function public.can_read_event_plan(uuid,uuid) to authenticated;
drop policy event_plans_customer_admin on public.event_plans;
create policy event_plans_customer_admin on public.event_plans for select to authenticated using(public.can_read_event_plan(id));
drop policy event_plan_items_participants on public.event_plan_items;
create policy event_plan_items_participants on public.event_plan_items for select to authenticated using(public.can_read_event_plan(plan_id,id));
create policy event_allocations_owner_read on public.event_equipment_allocations for select to authenticated using(
  exists(select 1 from public.event_equipment_items e where e.id=equipment_id and e.owner_id=public.current_owner_id())
);

create or replace function public.guard_event_catalog_approval()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_table_name='event_equipment_items' then
    if new.publication_status='published' and new.verification_status<>'verified' then raise exception 'Verify equipment before publication'; end if;
  elsif tg_table_name='event_service_offerings' then
    if new.publication_status='published' and not exists(select 1 from public.event_service_profiles where id=new.provider_id and verification_status='verified' and is_active) then raise exception 'Verify the professional before publication'; end if;
  end if;
  if auth.role()='service_role' or public.has_admin_permission('events.manage') then return new; end if;
  if tg_op='INSERT' then
    if coalesce(to_jsonb(new)->>'verification_status','pending')<>'pending'
      or coalesce(to_jsonb(new)->>'publication_status','draft')<>'draft' then
      raise exception 'Coordinator approval is required';
    end if;
  else
    if (to_jsonb(new)->'verification_status') is distinct from (to_jsonb(old)->'verification_status')
      or (to_jsonb(new)->'publication_status') is distinct from (to_jsonb(old)->'publication_status') then
      raise exception 'Only an Events coordinator can change approval or publication';
    end if;
    -- Material changes to a reviewed catalogue entry go back through review.
    if tg_table_name='event_equipment_items' then
      if (to_jsonb(new)-'updated_at') is distinct from (to_jsonb(old)-'updated_at') then
        new.verification_status:='pending'; new.publication_status:='draft';
      end if;
    elsif tg_table_name='event_service_profiles' then
      if (to_jsonb(new)-'updated_at') is distinct from (to_jsonb(old)-'updated_at') then new.verification_status:='pending'; end if;
    elsif (to_jsonb(new)-'updated_at') is distinct from (to_jsonb(old)-'updated_at') then new.publication_status:='draft';
    end if;
  end if;
  return new;
end $$;
create trigger guard_event_equipment_approval before insert or update on public.event_equipment_items for each row execute function public.guard_event_catalog_approval();
create trigger guard_event_provider_approval before insert or update on public.event_service_profiles for each row execute function public.guard_event_catalog_approval();
create trigger guard_event_offering_approval before insert or update on public.event_service_offerings for each row execute function public.guard_event_catalog_approval();

-- Private helper: every inventory path uses the same resource locks, excludes
-- its own prior allocation, and checks current stock before extending a hold.
create or replace function public.reserve_event_item_inventory(p_item_id uuid,p_expires_at timestamptz,p_confirm boolean default false)
returns void language plpgsql security definer set search_path=public as $$
declare i public.event_plan_items; p public.event_plans; e public.event_equipment_items;
  s public.event_service_profiles; c record; resource uuid; used integer; stock integer; occupied tstzrange; buffer integer;
begin
  select * into i from public.event_plan_items where id=p_item_id for update;
  select * into p from public.event_plans where id=i.plan_id for update;
  if p.id is null or p.status in('cancelled','completed','disputed') or lower(p.event_period)<=now() then raise exception 'Event is not available for reservation'; end if;
  if not p_confirm and (p_expires_at is null or p_expires_at<=now()) then raise exception 'Future inventory expiry required'; end if;
  if i.item_kind='equipment' then
    select * into e from public.event_equipment_items where id=i.equipment_id;
    if e.id is null or e.verification_status<>'verified' or e.publication_status<>'published' or not e.is_active then raise exception 'Equipment is not publicly bookable'; end if;
    occupied:=tstzrange(lower(p.event_period)-make_interval(mins=>e.setup_minutes),upper(p.event_period)+make_interval(mins=>e.return_buffer_minutes),'[)');
    for resource in select equipment_id from (
      select e.id equipment_id union select component_id from public.event_equipment_bundle_components where bundle_id=e.id
    ) x order by equipment_id loop perform pg_advisory_xact_lock(hashtextextended(resource::text,0)); end loop;
    for c in select equipment_id,sum(quantity)::integer quantity from (
      select e.id equipment_id,i.requested_quantity quantity
      union all select component_id,quantity_per_bundle*i.requested_quantity from public.event_equipment_bundle_components where bundle_id=e.id
    ) x group by equipment_id order by equipment_id loop
      select total_quantity into stock from public.event_equipment_items where id=c.equipment_id and is_active for update;
      select coalesce(sum(a.quantity),0)::integer into used from public.event_equipment_allocations a
      where a.equipment_id=c.equipment_id and a.plan_item_id<>i.id and a.status in('held','confirmed') and a.occupied_period&&occupied and (a.expires_at is null or a.expires_at>now());
      if stock is null or c.quantity<=0 or used+c.quantity>stock then raise exception 'Insufficient equipment quantity for requested period' using errcode='23P01'; end if;
      insert into public.event_equipment_allocations(plan_item_id,equipment_id,quantity,occupied_period,status,expires_at)
      values(i.id,c.equipment_id,c.quantity,occupied,case when p_confirm then 'confirmed' else 'held' end,case when p_confirm then null else p_expires_at end)
      on conflict(plan_item_id,equipment_id) do update set quantity=excluded.quantity,occupied_period=excluded.occupied_period,status=excluded.status,expires_at=excluded.expires_at;
    end loop;
  else
    select sp.* into s from public.event_service_offerings o join public.event_service_profiles sp on sp.id=o.provider_id
    where o.id=i.offering_id and o.is_active and o.publication_status='published' and sp.is_active and sp.verification_status='verified';
    if s.id is null then raise exception 'Service is not publicly bookable'; end if;
    perform pg_advisory_xact_lock(hashtextextended(s.id::text,0));
    select coalesce(travel_buffer_minutes,60) into buffer from public.event_service_bookings where plan_item_id=i.id;
    buffer:=coalesce(buffer,60);
    occupied:=tstzrange(lower(p.event_period)-make_interval(mins=>buffer),upper(p.event_period)+make_interval(mins=>buffer),'[)');
    if exists(select 1 from public.event_provider_unavailability where provider_id=s.id and unavailable_period&&occupied)
      or exists(select 1 from public.event_service_bookings b where b.provider_id=s.id and b.plan_item_id<>i.id and b.status in('held','confirmed') and b.service_period&&occupied and (b.expires_at is null or b.expires_at>now())) then
      raise exception 'Provider is unavailable for requested period' using errcode='23P01';
    end if;
    insert into public.event_service_bookings(plan_item_id,provider_id,service_period,status,expires_at,travel_buffer_minutes)
    values(i.id,s.id,occupied,case when p_confirm then 'confirmed' else 'held' end,case when p_confirm then null else p_expires_at end,buffer)
    on conflict(plan_item_id) do update set provider_id=excluded.provider_id,service_period=excluded.service_period,status=excluded.status,expires_at=excluded.expires_at;
  end if;
end $$;
revoke all on function public.reserve_event_item_inventory(uuid,timestamptz,boolean) from public,anon,authenticated;

create or replace function public.reserve_event_plan_inventory(p_plan_id uuid,p_expires_at timestamptz,p_confirm boolean default false)
returns void language plpgsql security definer set search_path=public as $$
declare resource uuid; i record;
begin
  perform 1 from public.event_plans where id=p_plan_id for update;
  if not exists(select 1 from public.event_plan_items where plan_id=p_plan_id)
    or exists(select 1 from public.event_plan_items where plan_id=p_plan_id and is_required and status not in('provider_confirmed','customer_accepted')) then raise exception 'Required providers have not all confirmed'; end if;
  -- Lock the complete resource set in one order for multi-provider plans.
  for resource in
    select id from (
      select equipment_id id from public.event_plan_items where plan_id=p_plan_id and item_kind='equipment' and status in('provider_confirmed','customer_accepted')
      union select b.component_id from public.event_equipment_bundle_components b join public.event_plan_items x on x.equipment_id=b.bundle_id where x.plan_id=p_plan_id and x.status in('provider_confirmed','customer_accepted')
      union select o.provider_id from public.event_service_offerings o join public.event_plan_items x on x.offering_id=o.id where x.plan_id=p_plan_id and x.status in('provider_confirmed','customer_accepted')
    ) resources order by id
  loop perform pg_advisory_xact_lock(hashtextextended(resource::text,0)); end loop;
  for i in select id from public.event_plan_items where plan_id=p_plan_id and status in('provider_confirmed','customer_accepted') order by id loop
    perform public.reserve_event_item_inventory(i.id,p_expires_at,p_confirm);
  end loop;
end $$;
revoke all on function public.reserve_event_plan_inventory(uuid,timestamptz,boolean) from public,anon,authenticated;

create or replace function public.confirm_event_equipment_item(p_plan_item_id uuid,p_hold_minutes integer default 1440)
returns setof public.event_equipment_allocations language plpgsql security definer set search_path=public as $$
declare i public.event_plan_items; p public.event_plans;
begin
  select * into i from public.event_plan_items where id=p_plan_item_id;
  select * into p from public.event_plans where id=i.plan_id for update;
  if i.id is null or i.item_kind<>'equipment' or i.status not in('requested','quoted','provider_confirmed') or p.status not in('draft','quote_requested','provider_review','partially_confirmed','fully_confirmed') then raise exception 'Pending equipment request required'; end if;
  if not exists(select 1 from public.event_equipment_items where id=i.equipment_id and owner_id=public.current_owner_id()) and not public.has_admin_permission('events.manage') then raise exception 'Equipment owner access required'; end if;
  perform public.reserve_event_item_inventory(i.id,now()+make_interval(mins=>least(greatest(p_hold_minutes,15),4320)),false);
  update public.event_plan_items set status='provider_confirmed' where id=i.id;
  update public.event_plans set status=case when exists(select 1 from public.event_plan_items where plan_id=p.id and is_required and status<>'provider_confirmed') then 'partially_confirmed' else 'fully_confirmed' end,updated_at=now() where id=p.id;
  return query select * from public.event_equipment_allocations where plan_item_id=i.id;
end $$;

create or replace function public.confirm_event_service_item(p_plan_item_id uuid,p_travel_buffer_minutes integer default 0,p_hold_minutes integer default 1440)
returns public.event_service_bookings language plpgsql security definer set search_path=public as $$
declare i public.event_plan_items; p public.event_plans; r public.event_service_bookings;
begin
  select * into i from public.event_plan_items where id=p_plan_item_id;
  select * into p from public.event_plans where id=i.plan_id for update;
  if i.id is null or i.item_kind<>'service' or i.status not in('requested','quoted','provider_confirmed') or p.status not in('draft','quote_requested','provider_review','partially_confirmed','fully_confirmed') then raise exception 'Pending service request required'; end if;
  if not exists(select 1 from public.event_service_offerings o join public.event_service_profiles s on s.id=o.provider_id where o.id=i.offering_id and s.profile_id=auth.uid()) and not public.has_admin_permission('events.manage') then raise exception 'Service provider access required'; end if;
  update public.event_service_bookings set travel_buffer_minutes=least(greatest(p_travel_buffer_minutes,0),1440) where plan_item_id=i.id;
  perform public.reserve_event_item_inventory(i.id,now()+make_interval(mins=>least(greatest(p_hold_minutes,15),4320)),false);
  update public.event_plan_items set status='provider_confirmed' where id=i.id;
  update public.event_plans set status=case when exists(select 1 from public.event_plan_items where plan_id=p.id and is_required and status<>'provider_confirmed') then 'partially_confirmed' else 'fully_confirmed' end,updated_at=now() where id=p.id;
  select * into r from public.event_service_bookings where plan_item_id=i.id; return r;
end $$;

-- Quotes reserve every selected provider until their expiry plus checkout time.
create or replace function public.guard_event_quote_inventory()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status='sent' and (tg_op='INSERT' or old.status is distinct from new.status) then
    if new.expires_at<=now() or new.expires_at>now()+interval '7 days' then raise exception 'Quotation expiry must be within seven days'; end if;
    perform public.reserve_event_plan_inventory(new.plan_id,new.expires_at+interval '60 minutes',false);
  elsif new.status='accepted' and old.status is distinct from new.status then
    if new.expires_at<=now() then raise exception 'Quotation has expired'; end if;
    perform public.reserve_event_plan_inventory(new.plan_id,greatest(new.expires_at,now())+interval '60 minutes',false);
  end if;
  return new;
end $$;
create trigger guard_event_quote_inventory before insert or update on public.event_quote_revisions for each row execute function public.guard_event_quote_inventory();

create or replace function public.sync_individual_booking_after_agreement()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status='sent' and (tg_op='INSERT' or old.status is distinct from new.status) then
    update public.event_individual_bookings set status='agreement_sent',updated_at=now() where plan_id=new.plan_id and status='quote_accepted';
  end if;
  -- Agreement acceptance alone never confirms a payment-dependent booking.
  return new;
end $$;

create or replace function public.accept_event_agreement(p_agreement_id uuid)
returns public.event_plans language plpgsql security definer set search_path=public as $$
declare a public.event_agreements; p public.event_plans; q public.event_quote_revisions; online boolean; paid bigint; deposit bigint;
begin
  select * into a from public.event_agreements where id=p_agreement_id;
  select * into p from public.event_plans where id=a.plan_id and customer_id=auth.uid() for update;
  if p.id is null or a.status<>'sent' or p.status<>'agreement_pending' or a.quote_revision_id is distinct from p.accepted_quote_revision_id then raise exception 'Event agreement is unavailable'; end if;
  select * into q from public.event_quote_revisions where id=p.accepted_quote_revision_id and status='accepted';
  if q.id is null then raise exception 'Accepted quotation required'; end if;
  if exists(select 1 from public.financial_reconciliation_cases c join public.payment_intents x on x.id=c.payment_intent_id where x.resource_type='event_plan' and x.resource_id=p.id and c.status in('open','investigating')) then raise exception 'Finance must review the earlier event payment first'; end if;
  select coalesce(sum(amount_minor),0) into paid from public.payment_intents where resource_type='event_plan' and resource_id=p.id and product in('event_deposit','event_balance') and status='verified_paid';
  select deposit_minor into deposit from public.calculate_booking_split(round(q.total_tzs)::bigint,25);
  online:=public.kodimali_feature_enabled('event_deposit_payments') and coalesce((select event_payments_enabled from public.marketplace_settings where id=true),false) and deposit>paid;
  perform public.reserve_event_plan_inventory(p.id,now()+interval '60 minutes',not online);
  update public.event_agreements set status='accepted',accepted_by=auth.uid(),accepted_at=now() where id=a.id;
  update public.event_plans set status=case when online then 'payment_pending' else 'confirmed' end,updated_at=now() where id=p.id returning * into p;
  update public.event_individual_bookings set status=case when online then 'agreement_sent' else 'confirmed' end,payment_status=case when online then 'pending' when paid>0 then 'paid' else 'offline_arrangement' end,updated_at=now() where plan_id=p.id;
  insert into public.event_audit_log(plan_id,actor_id,action,details) values(p.id,auth.uid(),'agreement.accepted',jsonb_build_object('agreement_id',a.id,'payment_required',online,'offline_arrangement',not online));
  return p;
end $$;

-- Keep the existing typed financial implementation and add inventory validation.
alter function public.prepare_event_payment_intent(uuid,text,text) rename to prepare_event_payment_intent_before_events_repair;
revoke all on function public.prepare_event_payment_intent_before_events_repair(uuid,text,text) from public,anon,authenticated,service_role;
create function public.prepare_event_payment_intent(p_plan_id uuid,p_product text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb; p public.event_plans; q public.event_quote_revisions; a public.event_agreements; paid bigint; deposit bigint; amount bigint; hold_minutes integer; intent public.payment_intents;
begin
  if p_product not in('event_deposit','event_balance') or not public.kodimali_feature_enabled(case when p_product='event_deposit' then 'event_deposit_payments' else 'event_balance_payments' end) then raise exception 'This event payment product is not enabled'; end if;
  if nullif(trim(p_idempotency_key),'') is null then raise exception 'Idempotency key required'; end if;
  select * into p from public.event_plans where id=p_plan_id and customer_id=auth.uid() for update;
  if p.id is null or p.status not in('payment_pending','confirmed') then raise exception 'Event is not payable'; end if;
  select * into q from public.event_quote_revisions where id=p.accepted_quote_revision_id and status='accepted';
  select * into a from public.event_agreements where plan_id=p.id and quote_revision_id=q.id and status='accepted' order by version desc limit 1;
  if q.id is null or a.id is null then raise exception 'Accepted quotation and agreement required'; end if;
  select coalesce(sum(amount_minor),0) into paid from public.payment_intents where resource_type='event_plan' and resource_id=p.id and product in('event_deposit','event_balance') and status='verified_paid';
  select deposit_minor into deposit from public.calculate_booking_split(round(q.total_tzs)::bigint,25);
  if p_product='event_balance' and paid<deposit then raise exception 'The event deposit must be verified first'; end if;
  amount:=greatest(0,case when p_product='event_deposit' then deposit else round(q.total_tzs)::bigint end-paid);
  if amount=0 then raise exception 'No payable amount remains for this event payment'; end if;
  hold_minutes:=public.resolve_booking_hold_minutes(null,case when p_product='event_deposit' then 'event_deposit_payments' else 'event_balance_payments' end);
  if p_product='event_deposit' then perform public.reserve_event_plan_inventory(p.id,now()+make_interval(mins=>hold_minutes),false); end if;
  insert into public.payment_intents(customer_id,product,resource_type,resource_id,amount_minor,currency,status,idempotency_key,metadata,expires_at)
  values(auth.uid(),p_product,'event_plan',p.id,amount,'TZS','awaiting_payment',trim(p_idempotency_key),jsonb_build_object('event_reference',p.reference,'quote_revision_id',q.id,'quote_revision',q.revision,'agreement_id',a.id,'agreement_version',a.version,'agreed_total_minor',round(q.total_tzs)::bigint,'deposit_percent',25,'credited_minor',paid,'hold_minutes',hold_minutes),now()+make_interval(mins=>hold_minutes))
  on conflict(idempotency_key) do update set updated_at=now() returning * into intent;
  if intent.customer_id<>auth.uid() or intent.resource_id<>p.id or intent.product<>p_product or intent.amount_minor<>amount or intent.metadata->>'quote_revision_id' is distinct from q.id::text then raise exception 'Idempotency key belongs to a different event payment'; end if;
  return jsonb_build_object('payment_intent_id',intent.id,'amount_minor',intent.amount_minor,'currency',intent.currency,'product',intent.product,'expires_at',intent.expires_at,'agreed_total_minor',round(q.total_tzs)::bigint,'deposit_minor',deposit,'balance_minor',greatest(0,round(q.total_tzs)::bigint-greatest(paid,deposit)));
end $$;
grant execute on function public.prepare_event_payment_intent(uuid,text,text) to authenticated,service_role;
revoke all on function public.prepare_event_payment_intent(uuid,text,text) from public,anon;

alter function public.finalize_platform_payment(uuid,text,jsonb) rename to finalize_platform_payment_before_events_repair;
revoke all on function public.finalize_platform_payment_before_events_repair(uuid,text,jsonb) from public,anon,authenticated,service_role;
create function public.finalize_platform_payment(p_order_id uuid,p_provider_transaction_id text,p_provider_payload jsonb default '{}'::jsonb)
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
revoke all on function public.finalize_platform_payment(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.finalize_platform_payment(uuid,text,jsonb) to service_role;

-- One idempotent transaction replaces create-plan/add-item/request-quote loops.
create table public.event_plan_submissions(
  customer_id uuid not null references public.profiles(id),idempotency_key text not null,
  request_payload jsonb not null,plan_id uuid not null references public.event_plans(id),
  created_at timestamptz not null default now(),primary key(customer_id,idempotency_key)
);
alter table public.event_plan_submissions enable row level security;
create function public.submit_event_plan(p_event_type_id uuid,p_start_at timestamptz,p_end_at timestamptz,p_location_id uuid,p_title text,p_items jsonb,p_idempotency_key text)
returns public.event_plans language plpgsql security definer set search_path=public as $$
declare p public.event_plans; entry jsonb; saved public.event_plan_submissions; payload jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if nullif(trim(p_idempotency_key),'') is null or length(p_idempotency_key)>200 then raise exception 'Submission key required'; end if;
  payload:=jsonb_build_object('type',p_event_type_id,'start',p_start_at,'end',p_end_at,'location',p_location_id,'title',p_title,'items',p_items);
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':'||p_idempotency_key,0));
  select * into saved from public.event_plan_submissions where customer_id=auth.uid() and idempotency_key=p_idempotency_key;
  if saved.plan_id is not null then
    if saved.request_payload<>payload then raise exception 'Submission key belongs to a different event'; end if;
    select * into p from public.event_plans where id=saved.plan_id; return p;
  end if;
  if p_start_at is null or p_start_at<=now() or p_end_at is null or p_end_at<=p_start_at then raise exception 'Valid future event period required'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>100 then raise exception 'Select between one and 100 items'; end if;
  p:=public.create_event_plan(p_event_type_id,p_start_at,p_end_at,p_location_id,null,1,null,p_title);
  for entry in select value from jsonb_array_elements(p_items) loop
    if entry->>'kind'='equipment' then
      if not exists(select 1 from public.event_equipment_items where id=(entry->>'id')::uuid and verification_status='verified' and publication_status='published' and is_active and total_quantity>=(entry->>'quantity')::integer) then raise exception 'Selected equipment is unavailable'; end if;
      perform public.add_event_plan_item(p.id,'equipment',(entry->>'id')::uuid,null,(entry->>'quantity')::integer,true,null);
    elsif entry->>'kind'='service' then
      if not exists(select 1 from public.event_service_offerings o join public.event_service_profiles s on s.id=o.provider_id where o.id=(entry->>'id')::uuid and o.is_active and o.publication_status='published' and s.is_active and s.verification_status='verified') then raise exception 'Selected professional is unavailable'; end if;
      perform public.add_event_plan_item(p.id,'service',null,(entry->>'id')::uuid,null,true,null);
    else raise exception 'Invalid event item'; end if;
  end loop;
  p:=public.request_event_quote(p.id);
  insert into public.event_plan_submissions(customer_id,idempotency_key,request_payload,plan_id) values(auth.uid(),p_idempotency_key,payload,p.id);
  return p;
end $$;
revoke all on function public.submit_event_plan(uuid,timestamptz,timestamptz,uuid,text,jsonb,text) from public,anon;
grant execute on function public.submit_event_plan(uuid,timestamptz,timestamptz,uuid,text,jsonb,text) to authenticated;

-- Event-only paths: a verified equipment owner need not become an agent.
create or replace function public.can_write_event_media(p_path text)
returns boolean language sql stable security definer set search_path=public as $$
  select split_part(p_path,'/',1)=auth.uid()::text and split_part(p_path,'/',2)='events' and (
    (split_part(p_path,'/',3)='equipment' and exists(select 1 from public.event_equipment_items e join public.owner_profiles o on o.id=e.owner_id where e.id::text=split_part(p_path,'/',4) and o.profile_id=auth.uid() and o.verification_status='verified'))
    or (split_part(p_path,'/',3)='professionals' and exists(select 1 from public.event_service_profiles s where s.id::text=split_part(p_path,'/',4) and s.profile_id=auth.uid()))
  );
$$;
revoke all on function public.can_write_event_media(text) from public,anon;
grant execute on function public.can_write_event_media(text) to authenticated;
create policy event_owner_media_write on storage.objects for all to authenticated
using(bucket_id='listing-media' and public.can_write_event_media(name))
with check(bucket_id='listing-media' and public.can_write_event_media(name));
create policy event_published_media_read on storage.objects for select to anon,authenticated using(
  bucket_id='listing-media' and (
    exists(select 1 from public.event_equipment_items e where e.verification_status='verified' and e.publication_status='published' and e.is_active and e.media_paths ? name)
    or exists(select 1 from public.event_service_profiles s where s.verification_status='verified' and s.is_active and s.portfolio_media ? name)
  )
);
