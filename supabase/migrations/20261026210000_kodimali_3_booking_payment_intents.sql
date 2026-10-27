-- KODIMALI 3.0 phase 6: server-authoritative deposit/balance payment intents.
-- Both products remain disabled until their feature flags are approved.

do $$ declare c text; begin
 for c in select conname from pg_constraint where conrelid='public.platform_payment_orders'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%purpose%'
 loop execute format('alter table public.platform_payment_orders drop constraint %I',c); end loop;
 alter table public.platform_payment_orders add constraint platform_payment_orders_purpose_check
 check(purpose in ('booking_reservation','booking_deposit','booking_balance','event_deposit','event_balance'));
end $$;

create or replace function public.prepare_booking_payment_intent(p_booking_id uuid,p_product text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare b public.booking_requests;s public.booking_terms_snapshots;amount bigint;paid_deposit bigint;paid_balance bigint;intent public.payment_intents;asset uuid;hold_until timestamptz;
begin
 if p_product not in ('booking_deposit','booking_balance') then raise exception 'Unsupported booking payment product'; end if;
 if not public.kodimali_feature_enabled(case when p_product='booking_deposit' then 'booking_deposit_payments' else 'booking_balance_payments' end) then raise exception 'This booking payment product is not enabled'; end if;
 if nullif(trim(p_idempotency_key),'') is null then raise exception 'Idempotency key is required'; end if;
 select * into b from public.booking_requests where id=p_booking_id and customer_id=auth.uid() for update;
 if b.id is null then raise exception 'Booking was not found'; end if;
 select * into s from public.booking_terms_snapshots where booking_request_id=b.id and status='accepted';
 if s.id is null then raise exception 'Accepted booking terms are required before payment'; end if;
 select coalesce(sum(amount_minor),0) into paid_deposit from public.payment_intents where resource_type='booking_request' and resource_id=b.id and product='booking_deposit' and status='verified_paid';
 select coalesce(sum(amount_minor),0) into paid_balance from public.payment_intents where resource_type='booking_request' and resource_id=b.id and product='booking_balance' and status='verified_paid';
 amount:=case when p_product='booking_deposit' then greatest(0,s.deposit_minor-paid_deposit) else greatest(0,s.balance_minor-paid_balance) end;
 if amount<=0 then raise exception 'No payable amount remains for this product'; end if;
 if p_product='booking_balance' and paid_deposit<s.deposit_minor then raise exception 'The booking deposit must be verified first'; end if;
 select asset_id into asset from public.listings where id=b.listing_id;
 if asset is null then raise exception 'Listing is not connected to reservable inventory'; end if;
 if p_product='booking_deposit' then
  update public.asset_reservations r set status='expired',updated_at=now() from public.booking_requests x where r.booking_request_id=x.id and r.status='held' and x.payment_expires_at<=now();
  if exists(select 1 from public.asset_reservations r where r.asset_id=asset and r.booking_request_id<>b.id and r.status in ('held','confirmed') and r.occupied_period&&tstzrange(b.requested_start_at,b.requested_end_at,'[)')) then raise exception 'The selected period is no longer available' using errcode='23P01'; end if;
  hold_until:=now()+interval '30 minutes';
  insert into public.asset_reservations(asset_id,booking_request_id,occupied_period,status,created_by) values(asset,b.id,tstzrange(b.requested_start_at,b.requested_end_at,'[)'),'held',auth.uid())
  on conflict(booking_request_id) do update set occupied_period=excluded.occupied_period,status=case when public.asset_reservations.status='confirmed' then 'confirmed' else 'held' end,updated_at=now();
  update public.booking_requests set booking_status='reserved',payment_expires_at=hold_until,payment_ready_at=coalesce(payment_ready_at,now()),updated_at=now() where id=b.id;
 end if;
 insert into public.payment_intents(customer_id,product,resource_type,resource_id,amount_minor,idempotency_key,agreement_snapshot_id,status,expires_at,metadata)
 values(auth.uid(),p_product,'booking_request',b.id,amount,trim(p_idempotency_key),s.id,'awaiting_payment',case when p_product='booking_deposit' then hold_until else s.balance_due_at end,jsonb_build_object('booking_reference',b.request_reference,'terms_version',s.version))
 on conflict(idempotency_key) do update set updated_at=now() returning * into intent;
 if intent.customer_id<>auth.uid() or intent.resource_id<>b.id or intent.product<>p_product or intent.amount_minor<>amount then raise exception 'Idempotency key belongs to a different payment request'; end if;
 return jsonb_build_object('payment_intent_id',intent.id,'amount_minor',intent.amount_minor,'currency',intent.currency,'product',intent.product,'expires_at',intent.expires_at,'hold_expires_at',hold_until);
end $$;
revoke all on function public.prepare_booking_payment_intent(uuid,text,text) from public;
grant execute on function public.prepare_booking_payment_intent(uuid,text,text) to authenticated;

create or replace function public.finalize_platform_payment(p_order_id uuid,p_provider_transaction_id text,p_provider_payload jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare o public.platform_payment_orders;b public.booking_requests;asset uuid;obligation_kind text;i public.payment_intents;j uuid;cash uuid;liability uuid;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required'; end if;
 select * into o from public.platform_payment_orders where id=p_order_id for update;
 if o.id is null then raise exception 'Payment order not found'; end if;
 if o.status='paid' then return; end if;
 if nullif(trim(p_provider_transaction_id),'') is null then raise exception 'Provider transaction ID is required'; end if;
 if exists(select 1 from public.platform_payment_orders x where x.provider_transaction_id=p_provider_transaction_id and x.id<>o.id) then raise exception 'Provider transaction ID is already used'; end if;
 if o.payment_intent_id is not null then
  select * into i from public.payment_intents where id=o.payment_intent_id for update;
  if i.id is null or i.customer_id<>o.user_id or i.amount_minor<>round(o.amount_tzs)::bigint or i.currency<>o.currency then raise exception 'Payment intent does not match provider order'; end if;
 end if;
 update public.platform_payment_orders set status='paid',provider_transaction_id=trim(p_provider_transaction_id),provider_response=coalesce(p_provider_payload,'{}'),paid_at=now(),updated_at=now() where id=o.id;
 if o.purpose in ('booking_deposit','booking_balance') then
  if i.product<>o.purpose or i.resource_type<>'booking_request' or i.resource_id<>o.resource_id then raise exception 'Booking payment purpose mismatch'; end if;
  select * into b from public.booking_requests where id=o.resource_id for update;
  if b.customer_id<>o.user_id then raise exception 'Booking payment owner mismatch'; end if;
  select asset_id into asset from public.listings where id=b.listing_id;
  insert into public.booking_payment_transactions(booking_request_id,provider,provider_reference,kind,amount_tzs,status,verified_at,paid_at,payment_order_id,provider_payload)
  values(b.id,'sonicpesa',trim(p_provider_transaction_id),case when o.purpose='booking_deposit' then 'deposit' else 'balance' end,o.amount_tzs,'paid',now(),now(),o.id,coalesce(p_provider_payload,'{}')) on conflict(provider,provider_reference) do nothing;
  update public.payment_intents set status='verified_paid',provider='sonicpesa',provider_order_id=o.provider_order_id,provider_transaction_id=trim(p_provider_transaction_id),verified_at=now(),updated_at=now() where id=i.id;
  if o.purpose='booking_deposit' then
   insert into public.asset_reservations(asset_id,booking_request_id,occupied_period,status,created_by) values(asset,b.id,tstzrange(b.requested_start_at,b.requested_end_at,'[)'),'confirmed',o.user_id)
   on conflict(booking_request_id) do update set status='confirmed',updated_at=now();
   update public.booking_requests set booking_status='confirmed',updated_at=now() where id=b.id;
  end if;
  select id into cash from public.financial_accounts where code='CASH_PROVIDER_CLEARING';
  select id into liability from public.financial_accounts where code='BOOKING_COLLECTIONS_LIABILITY';
  insert into public.financial_journals(journal_type,reference_type,reference_id,idempotency_key,description,posted_by,metadata)
  values('payment_collection','payment_intent',i.id,'payment:'||i.id::text,'Verified '||replace(i.product,'_',' ')||' collection',o.user_id,jsonb_build_object('provider_order_id',o.provider_order_id,'provider_transaction_id',p_provider_transaction_id)) returning id into j;
  insert into public.financial_postings(journal_id,account_id,debit_minor,memo) values(j,cash,i.amount_minor,'Provider clearing increased');
  insert into public.financial_postings(journal_id,account_id,credit_minor,memo) values(j,liability,i.amount_minor,'Booking funds pending allocation');
 elsif o.purpose='booking_reservation' then
  select * into b from public.booking_requests where id=o.resource_id for update;
  if b.customer_id<>o.user_id then raise exception 'Booking payment owner mismatch'; end if;
  select asset_id into asset from public.listings where id=b.listing_id;
  insert into public.booking_payment_transactions(booking_request_id,provider,provider_reference,kind,amount_tzs,status,verified_at,paid_at,payment_order_id,provider_payload)
  values(b.id,'sonicpesa',trim(p_provider_transaction_id),'reservation',o.amount_tzs,'paid',now(),now(),o.id,coalesce(p_provider_payload,'{}')) on conflict(provider,provider_reference) do nothing;
  insert into public.asset_reservations(asset_id,booking_request_id,occupied_period,status,created_by) values(asset,b.id,tstzrange(b.requested_start_at,b.requested_end_at,'[)'),'confirmed',o.user_id)
  on conflict(booking_request_id) do update set status='confirmed',updated_at=now();
  update public.booking_requests set booking_status='confirmed',updated_at=now() where id=b.id;
 elsif o.purpose in ('event_deposit','event_balance') then
  if o.payment_intent_id is not null then
   if i.product<>o.purpose or i.resource_type<>'event_plan' or i.resource_id<>o.resource_id then raise exception 'Event payment purpose mismatch'; end if;
   update public.payment_intents set status='verified_paid',provider='sonicpesa',provider_order_id=o.provider_order_id,provider_transaction_id=trim(p_provider_transaction_id),verified_at=now(),updated_at=now() where id=i.id;
  end if;
  obligation_kind:=case when o.purpose='event_deposit' then 'deposit' else 'balance' end;
  insert into public.event_payment_obligations(plan_id,kind,amount_tzs,due_at,status,collection_enabled,external_reference,payment_order_id)
  values(o.resource_id,obligation_kind,o.amount_tzs,now(),'paid',true,coalesce(nullif(trim(p_provider_transaction_id),''),o.provider_order_id),o.id);
  if o.purpose='event_deposit' then
   update public.event_equipment_allocations x set status='confirmed',expires_at=null from public.event_plan_items e where e.id=x.plan_item_id and e.plan_id=o.resource_id and x.status='held';
   update public.event_service_bookings x set status='confirmed',expires_at=null from public.event_plan_items e where e.id=x.plan_item_id and e.plan_id=o.resource_id and x.status='held';
   update public.event_plans set status='confirmed',updated_at=now() where id=o.resource_id;
   update public.event_individual_bookings set payment_status='paid',status='confirmed',updated_at=now() where plan_id=o.resource_id;
  end if;
  insert into public.event_audit_log(plan_id,actor_id,action,details) values(o.resource_id,o.user_id,'payment.confirmed',jsonb_build_object('payment_order_id',o.id,'purpose',o.purpose,'amount_tzs',o.amount_tzs));
  if o.payment_intent_id is not null then
   select id into cash from public.financial_accounts where code='CASH_PROVIDER_CLEARING';
   select id into liability from public.financial_accounts where code='BOOKING_COLLECTIONS_LIABILITY';
   insert into public.financial_journals(journal_type,reference_type,reference_id,idempotency_key,description,posted_by,metadata)
   values('payment_collection','payment_intent',i.id,'payment:'||i.id::text,'Verified '||replace(i.product,'_',' ')||' collection',o.user_id,jsonb_build_object('provider_order_id',o.provider_order_id,'provider_transaction_id',p_provider_transaction_id)) returning id into j;
   insert into public.financial_postings(journal_id,account_id,debit_minor,memo) values(j,cash,i.amount_minor,'Provider clearing increased');
   insert into public.financial_postings(journal_id,account_id,credit_minor,memo) values(j,liability,i.amount_minor,'Event funds pending allocation');
  end if;
 end if;
end $$;
revoke all on function public.finalize_platform_payment(uuid,text,jsonb) from public;
grant execute on function public.finalize_platform_payment(uuid,text,jsonb) to service_role;

comment on function public.prepare_booking_payment_intent(uuid,text,text) is 'Prepares exact 25% deposit or 75% balance from an accepted immutable terms snapshot; controlled by feature flags.';
