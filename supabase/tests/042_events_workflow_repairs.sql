-- Behavioral tests executed by scripts/test-events-workflows.py in a disposable
-- local database. Shared auth/payment prerequisites are supplied by that runner.
create function public.test_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
create function public.test_throws(statement text,fragment text) returns void language plpgsql as $$
begin
  begin execute statement; exception when others then
    if position(fragment in sqlerrm)>0 then raise notice 'PASS: rejected operation (%)',fragment; return; end if;
    raise exception 'Unexpected failure: % (wanted %)',sqlerrm,fragment;
  end;
  raise exception 'Statement unexpectedly succeeded: %',statement;
end $$;

select set_config('request.jwt.claim.role','service_role',false);
insert into public.profiles(id) select ('00000000-0000-0000-0000-'||lpad(x::text,12,'0'))::uuid from generate_series(1,6) x;
insert into public.test_permissions values('00000000-0000-0000-0000-000000000001','*');
insert into public.owner_profiles(id,profile_id,verification_status) values('10000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000003','verified');
insert into public.event_equipment_items(id,owner_id,category_id,name,condition,total_quantity,price_amount_tzs,price_unit,verification_status,publication_status,media_paths)
select ('20000000-0000-0000-0000-'||lpad(x::text,12,'0'))::uuid,'10000000-0000-0000-0000-000000000003',(select id from public.event_equipment_categories where slug='chairs'),'Chairs '||x,'good',100,1000,'item_event','verified','published','[]'::jsonb from generate_series(1,3) x;
insert into public.event_service_profiles(id,profile_id,display_name,provider_kind,verification_status) values('30000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000004','Test DJ','dj','verified');
insert into public.event_service_offerings(id,provider_id,title,pricing_mode,price_amount_tzs,publication_status) values('40000000-0000-0000-0000-000000000004','30000000-0000-0000-0000-000000000004','DJ evening','fixed',20000,'published');

set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
select public.test_throws($q$update public.event_equipment_items set verification_status='pending' where id='20000000-0000-0000-0000-000000000001'$q$,'before publication');
select public.test_throws($q$insert into public.event_equipment_items(owner_id,category_id,name,condition,total_quantity,price_amount_tzs,price_unit,verification_status,publication_status) select '10000000-0000-0000-0000-000000000003',id,'Bypass','good',5,1000,'item_event','verified','published' from public.event_equipment_categories limit 1$q$,'Coordinator approval');
insert into storage.objects(bucket_id,name) values('listing-media','00000000-0000-0000-0000-000000000003/events/equipment/20000000-0000-0000-0000-000000000001/cover.jpg');
select public.test_assert(exists(select 1 from storage.objects),'owner-only account uploads event media');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select public.test_throws($q$insert into storage.objects(bucket_id,name) values('listing-media','00000000-0000-0000-0000-000000000003/events/equipment/20000000-0000-0000-0000-000000000001/other.jpg')$q$,'row-level security');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',false);
select public.test_throws($q$update public.event_service_profiles set verification_status='pending' where id='30000000-0000-0000-0000-000000000004'$q$,'coordinator');
select public.test_throws($q$update public.event_service_offerings set publication_status='paused' where id='40000000-0000-0000-0000-000000000004'$q$,'coordinator');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
do $$ declare p public.event_plans; retry public.event_plans; total integer; individual public.event_individual_bookings; q public.event_quote_revisions; agreement public.event_agreements; p2 public.event_plans; item uuid; r public.event_substitution_proposals;
begin
  select count(*) into total from public.event_plans;
  perform public.test_throws(format('select public.submit_event_plan(%L,now()+interval ''10 days'',now()+interval ''10 days 2 hours'',null,''invalid'',%L,''failed'')',(select id from public.event_types where slug='wedding'),'[{"kind":"equipment","id":"20000000-0000-0000-0000-000000000001","quantity":10},{"kind":"service","id":"99999999-9999-9999-9999-999999999999"}]'),'unavailable');
  perform public.test_assert((select count(*) from public.event_plans)=total,'failed second item leaves no partial plan');
  p:=public.submit_event_plan((select id from public.event_types where slug='wedding'),date_trunc('day',now())+interval '10 days',date_trunc('day',now())+interval '10 days 2 hours',null,'Package','[{"kind":"equipment","id":"20000000-0000-0000-0000-000000000001","quantity":60},{"kind":"service","id":"40000000-0000-0000-0000-000000000004"}]','package');
  retry:=public.submit_event_plan((select id from public.event_types where slug='wedding'),date_trunc('day',now())+interval '10 days',date_trunc('day',now())+interval '10 days 2 hours',null,'Package','[{"kind":"equipment","id":"20000000-0000-0000-0000-000000000001","quantity":60},{"kind":"service","id":"40000000-0000-0000-0000-000000000004"}]','package');
  perform public.test_assert(p.id=retry.id,'package retry reuses plan');
  perform set_config('test.package',p.id::text,false);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
  select id into item from public.event_plan_items where plan_id=p.id and item_kind='equipment';
  perform public.confirm_event_equipment_item(item,1440);
  perform public.confirm_event_equipment_item(item,1440);
  perform public.test_assert((select sum(quantity) from public.event_equipment_allocations where plan_item_id=item)=60,'confirmation retry does not double-count own stock');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',false);
  select id into item from public.event_plan_items where plan_id=p.id and item_kind='service';
  perform public.confirm_event_service_item(item,60,1440);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
  q:=public.create_event_quote_revision(p.id,now()+interval '3 days',(select jsonb_agg(jsonb_build_object('plan_item_id',id,'description',item_kind,'quantity',coalesce(requested_quantity,1),'unit_price_tzs',1000)) from public.event_plan_items where plan_id=p.id),0);
  perform public.test_assert((select min(expires_at) from public.event_equipment_allocations where plan_item_id in(select id from public.event_plan_items where plan_id=p.id))>=q.expires_at,'quote extends stock holds through quote validity');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  perform public.accept_event_quote(q.id);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
  agreement:=public.send_event_agreement(p.id,'Terms');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  p:=public.accept_event_agreement(agreement.id);
  perform public.test_assert(p.status='payment_pending','online event agreement waits for payment');
  perform public.prepare_event_payment_intent(p.id,'event_deposit','package-payment');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000006',false);
  p2:=public.create_event_plan((select id from public.event_types where slug='wedding'),lower(p.event_period),upper(p.event_period),null,null,1,null,'Overlap');
  perform public.add_event_plan_item(p2.id,'equipment','20000000-0000-0000-0000-000000000001',null,60,true,null);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
  select id into item from public.event_plan_items where plan_id=p2.id;
  perform public.test_throws(format('select public.confirm_event_equipment_item(%L,1440)',item),'Insufficient');
  perform set_config('test.overlap',p2.id::text,false);
end $$;
reset role;

-- Reproduce a delayed payment after an expired hold has been reused.
update public.event_equipment_allocations set expires_at=now()-interval '1 minute' where plan_item_id in(select id from public.event_plan_items where plan_id=current_setting('test.package')::uuid);
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
select public.confirm_event_equipment_item((select id from public.event_plan_items where plan_id=current_setting('test.overlap')::uuid),1440);
reset role;
insert into public.platform_payment_orders(user_id,purpose,resource_id,order_reference,provider_order_id,amount_tzs,customer_phone_number,payment_intent_id)
select customer_id,'event_deposit',resource_id,'test-payment','provider-late',amount_minor,'255700000000',id from public.payment_intents where idempotency_key='package-payment';
select set_config('request.jwt.claim.role','service_role',false);
select public.finalize_platform_payment((select id from public.platform_payment_orders where order_reference='test-payment'),'late-transaction','{}');
select public.test_assert((select status='disputed' from public.event_plans where id=current_setting('test.package')::uuid),'late payment cannot revive unavailable stock');
select public.test_assert((select status='paid' from public.platform_payment_orders where order_reference='test-payment'),'late verified money is still recorded');
select public.test_assert(exists(select 1 from public.financial_reconciliation_cases),'late unavailable payment opens finance review');
select public.test_assert(not exists(select 1 from public.event_equipment_allocations where plan_item_id in(select id from public.event_plan_items where plan_id=current_setting('test.package')::uuid) and status='confirmed'),'unavailable original inventory stays unconfirmed');
select public.finalize_platform_payment((select id from public.platform_payment_orders where order_reference='test-payment'),'late-transaction','{}');
select public.test_assert((select count(*) from public.financial_reconciliation_cases)=1,'duplicate webhook does not duplicate finance review');

-- Individual agreement and explicit offline behavior, cancellation, replacement.
select set_config('request.jwt.claim.role','authenticated',false);
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
do $$ declare b public.event_individual_bookings; q public.event_quote_revisions; a public.event_agreements; p public.event_plans; r public.event_substitution_proposals; cancelled public.event_cancellations;
begin
  b:=public.create_individual_event_booking('equipment','20000000-0000-0000-0000-000000000002',null,now()+interval '11 days',now()+interval '11 days 2 hours',5,'Test');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
  perform public.respond_individual_event_booking(b.id,true,null);
  b:=public.send_individual_booking_quote(b.id,10000,'Terms',now()+interval '3 days');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  select * into q from public.event_quote_revisions where plan_id=b.plan_id and status='sent';
  perform public.accept_event_quote(q.id);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
  a:=public.send_event_agreement(b.plan_id,'Terms');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  p:=public.accept_event_agreement(a.id);
  perform public.test_assert((select status='agreement_sent' and payment_status='pending' from public.event_individual_bookings where id=b.id),'individual agreement does not confirm unpaid booking');
  perform set_config('test.individual',b.id::text,false);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
  cancelled:=public.provider_cancel_event_item(b.plan_item_id,'Supplier unavailable');
  perform public.test_assert(not exists(select 1 from public.event_equipment_allocations where plan_item_id=b.plan_item_id and status in('held','confirmed')),'supplier cancellation releases stock');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
  r:=public.propose_event_replacement(b.plan_item_id,'20000000-0000-0000-0000-000000000003','Replacement chairs',2000);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
  perform public.test_throws(format('select public.respond_event_replacement(%L,true)',r.id),'unavailable');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  r:=public.respond_event_replacement(r.id,true);
  perform public.test_assert(r.accepted_plan_item_id is not null,'customer replacement consent creates a new supplier request');
  perform public.test_assert((select status='requested' from public.event_plan_items where id=r.accepted_plan_item_id),'replacement still needs provider approval');
  perform public.test_assert((select accepted_quote_revision_id is null from public.event_plans where id=b.plan_id),'replacement invalidates old price consent');
  cancelled:=public.cancel_customer_event(b.plan_id,'No longer needed');
  perform public.test_assert((select status='cancelled' from public.event_plans where id=b.plan_id),'customer cancellation cancels plan');
end $$;
reset role;

select public.test_assert(not has_function_privilege('authenticated','public.reserve_event_plan_inventory(uuid,timestamptz,boolean)','EXECUTE'),'inventory helper is private');
select public.test_assert(not has_function_privilege('authenticated','public.finalize_platform_payment_before_events_repair(uuid,text,jsonb)','EXECUTE'),'old payment implementation cannot bypass inventory protection');
select public.test_assert(not has_function_privilege('authenticated','public.prepare_event_payment_intent_before_events_repair(uuid,text,text)','EXECUTE'),'old checkout implementation cannot bypass inventory protection');

-- A valid paid event and an explicitly disabled online-payment event.
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
do $$ declare b public.event_individual_bookings; q public.event_quote_revisions; a public.event_agreements; p public.event_plans; payment jsonb;
begin
  b:=public.create_individual_event_booking('equipment','20000000-0000-0000-0000-000000000002',null,now()+interval '15 days',now()+interval '15 days 2 hours',10,null);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
  perform public.respond_individual_event_booking(b.id,true,null);
  perform public.send_individual_booking_quote(b.id,10000,'Paid terms',now()+interval '3 days');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  select * into q from public.event_quote_revisions where plan_id=b.plan_id and status='sent';
  perform public.accept_event_quote(q.id);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
  a:=public.send_event_agreement(b.plan_id,'Terms');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  p:=public.accept_event_agreement(a.id);
  payment:=public.prepare_event_payment_intent(p.id,'event_deposit','valid-payment');
  perform set_config('test.valid_paid',p.id::text,false);
end $$;
reset role;
insert into public.platform_payment_orders(user_id,purpose,resource_id,order_reference,provider_order_id,amount_tzs,customer_phone_number,payment_intent_id)
select customer_id,'event_deposit',resource_id,'valid-payment','provider-valid',amount_minor,'255700000000',id from public.payment_intents where idempotency_key='valid-payment';
select set_config('request.jwt.claim.role','service_role',false);
select public.finalize_platform_payment((select id from public.platform_payment_orders where order_reference='valid-payment'),'valid-transaction','{}');
select public.test_assert((select status='confirmed' from public.event_plans where id=current_setting('test.valid_paid')::uuid),'verified valid deposit confirms plan');
select public.test_assert((select status='confirmed' and payment_status='paid' from public.event_individual_bookings where plan_id=current_setting('test.valid_paid')::uuid),'verified deposit synchronizes individual status');

update public.test_feature_flags set enabled=false;
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
do $$ declare b public.event_individual_bookings; q public.event_quote_revisions; a public.event_agreements; p public.event_plans; c public.event_cancellations;
begin
  b:=public.create_individual_event_booking('equipment','20000000-0000-0000-0000-000000000002',null,now()+interval '16 days',now()+interval '16 days 2 hours',10,null);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
  perform public.respond_individual_event_booking(b.id,true,null);
  perform public.send_individual_booking_quote(b.id,10000,'Offline terms',now()+interval '3 days');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  select * into q from public.event_quote_revisions where plan_id=b.plan_id and status='sent';
  perform public.accept_event_quote(q.id);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
  a:=public.send_event_agreement(b.plan_id,'Offline settlement by agreement');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  p:=public.accept_event_agreement(a.id);
  perform public.test_assert(p.status='confirmed' and (select payment_status='offline_arrangement' from public.event_individual_bookings where id=b.id),'disabled online collection records explicit offline arrangement');
  c:=public.cancel_customer_event(p.id,'Cancelled offline event');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
  perform public.record_event_cancellation_settlement(c.id,'review-no-platform-refund',0);
  perform public.test_assert((select status='completed' from public.event_cancellations where id=c.id),'finance records zero-refund review without claiming a transfer');
  perform public.test_throws(format('select public.record_event_cancellation_settlement(%L,''repeat'',0)',c.id),'Open cancellation');
end $$;
reset role;


-- Customer-approved replacements retain verified funds without collecting a
-- second deposit, and price changes cannot charge more than the remaining total.
select set_config('request.jwt.claim.role','service_role',false);
insert into public.event_service_offerings(id,provider_id,title,pricing_mode,price_amount_tzs,publication_status) values('40000000-0000-0000-0000-000000000005','30000000-0000-0000-0000-000000000004','Replacement DJ package','fixed',20000,'published');
update public.test_feature_flags set enabled=true;
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
do $$ declare item record; proposal public.event_substitution_proposals; q public.event_quote_revisions; a public.event_agreements; p public.event_plans; payment jsonb;
begin
  for item in select * from public.event_plan_items where plan_id=current_setting('test.package')::uuid and is_required loop
    proposal:=public.propose_event_replacement(item.id,case when item.item_kind='equipment' then '20000000-0000-0000-0000-000000000003'::uuid else '40000000-0000-0000-0000-000000000005'::uuid end,'Replacement after availability changed',0);
    perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
    perform public.respond_event_replacement(proposal.id,true);
    perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
  end loop;
  perform public.resolve_event_payment_review((select id from public.financial_reconciliation_cases where status='open' limit 1),'credit_for_replacement','customer-approved-credit');
  perform public.test_assert((select status='verified_paid' from public.payment_intents where idempotency_key='package-payment'),'finance retains customer-approved payment as replacement credit');
  for item in select * from public.event_plan_items where plan_id=current_setting('test.package')::uuid and is_required loop
    if item.item_kind='equipment' then perform public.confirm_event_equipment_item(item.id,1440); else perform public.confirm_event_service_item(item.id,60,1440); end if;
  end loop;
  q:=public.create_event_quote_revision(current_setting('test.package')::uuid,now()+interval '3 days',(select jsonb_agg(jsonb_build_object('plan_item_id',id,'description',item_kind,'quantity',coalesce(requested_quantity,1),'unit_price_tzs',1000)) from public.event_plan_items where plan_id=current_setting('test.package')::uuid and is_required),0);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  perform public.accept_event_quote(q.id);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
  a:=public.send_event_agreement(current_setting('test.package')::uuid,'Revised replacement terms');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  p:=public.accept_event_agreement(a.id);
  perform public.test_assert(p.status='confirmed','replacement deposit credit confirms only after new terms are accepted');
  payment:=public.prepare_event_payment_intent(p.id,'event_balance','replacement-balance');
  perform public.test_assert((payment->>'amount_minor')::bigint=45750,'remaining balance credits earlier verified money');
end $$;
reset role;

-- A balance arriving after cancellation is recorded for finance review; the
-- externally completed refund is journaled and duplicate webhooks stay terminal.
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select public.prepare_event_payment_intent(current_setting('test.valid_paid')::uuid,'event_balance','cancelled-balance');
select public.cancel_customer_event(current_setting('test.valid_paid')::uuid,'Cancelled before balance settled');
reset role;
insert into public.platform_payment_orders(user_id,purpose,resource_id,order_reference,provider_order_id,amount_tzs,customer_phone_number,payment_intent_id)
select customer_id,'event_balance',resource_id,'cancelled-balance','provider-cancelled-balance',amount_minor,'255700000000',id from public.payment_intents where idempotency_key='cancelled-balance';
select set_config('request.jwt.claim.role','service_role',false);
select public.finalize_platform_payment((select id from public.platform_payment_orders where order_reference='cancelled-balance'),'cancelled-balance-transaction','{}');
select set_config('request.jwt.claim.role','authenticated',false);
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select public.resolve_event_payment_review((select id from public.financial_reconciliation_cases where status='open' limit 1),'refund_recorded','external-full-balance-refund');
select public.test_assert((select status='refunded' from public.payment_intents where idempotency_key='cancelled-balance'),'late cancelled-event balance has an explicit recorded refund');
select public.record_event_cancellation_settlement((select id from public.event_cancellations where plan_id=current_setting('test.valid_paid')::uuid limit 1),'external-deposit-refund',2500);
select public.test_assert((select sum(amount_tzs) from public.event_payment_obligations where plan_id=current_setting('test.valid_paid')::uuid and kind='refund' and status='refunded')=10000,'cancellation refund cannot count the same money twice');
reset role;
select set_config('request.jwt.claim.role','service_role',false);
select public.finalize_platform_payment((select id from public.platform_payment_orders where order_reference='cancelled-balance'),'cancelled-balance-transaction','{}');
select public.test_assert((select status='refunded' from public.platform_payment_orders where order_reference='cancelled-balance'),'duplicate refunded webhook stays refunded');


set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
do $$ declare b public.event_individual_bookings; q public.event_quote_revisions; a public.event_agreements; p public.event_plans; result jsonb; retry public.event_plans;
begin
  p:=public.create_event_plan((select id from public.event_types where slug='wedding'),now()+interval '50 days',now()+interval '50 days 2 hours',null,null,1,null,'Mobile draft');
  perform public.add_event_plan_item(p.id,'equipment','20000000-0000-0000-0000-000000000002',null,1,true,null);
  perform public.test_throws(format('select public.submit_event_draft(%L,%L)',p.id,'[{"kind":"equipment","id":"20000000-0000-0000-0000-000000000002","quantity":5},{"kind":"service","id":"99999999-9999-9999-9999-999999999999"}]'),'unavailable');
  perform public.test_assert((select count(*) from public.event_plan_items where plan_id=p.id)=1,'failed mobile draft submission preserves the previous draft atomically');
  p:=public.submit_event_draft(p.id,'[{"kind":"equipment","id":"20000000-0000-0000-0000-000000000002","quantity":5}]');
  retry:=public.submit_event_draft(p.id,'[{"kind":"equipment","id":"20000000-0000-0000-0000-000000000002","quantity":5}]');
  perform public.test_assert(retry.id=p.id and (select count(*) from public.event_plan_items where plan_id=p.id)=1,'mobile draft retry does not duplicate components');

  b:=public.create_individual_event_booking('equipment','20000000-0000-0000-0000-000000000002',null,now()+interval '40 days',now()+interval '40 days 2 hours',10,null);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
  perform public.respond_individual_event_booking(b.id,true,null);
  perform public.send_individual_booking_quote(b.id,10000,'Original quote',now()+interval '3 days');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  select * into q from public.event_quote_revisions where plan_id=b.plan_id and status='sent';
  perform public.accept_event_quote(q.id);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
  a:=public.send_event_agreement(b.plan_id,'Original terms');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  perform public.accept_event_agreement(a.id);
  result:=public.prepare_event_payment_intent(b.plan_id,'event_deposit','superseded-quote-payment');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
  q:=public.create_event_quote_revision(b.plan_id,now()+interval '3 days',jsonb_build_array(jsonb_build_object('plan_item_id',b.plan_item_id,'description','New price','quantity',10,'unit_price_tzs',2000)),0);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  perform public.accept_event_quote(q.id);
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
  a:=public.send_event_agreement(b.plan_id,'New terms');
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
  perform public.accept_event_agreement(a.id);
  perform set_config('test.superseded_quote',b.plan_id::text,false);
end $$;
reset role;
insert into public.platform_payment_orders(user_id,purpose,resource_id,order_reference,provider_order_id,amount_tzs,customer_phone_number,payment_intent_id)
select customer_id,'event_deposit',resource_id,'superseded-quote','provider-superseded',amount_minor,'255700000000',id from public.payment_intents where idempotency_key='superseded-quote-payment';
select set_config('request.jwt.claim.role','service_role',false);
select public.finalize_platform_payment((select id from public.platform_payment_orders where order_reference='superseded-quote'),'superseded-quote-transaction','{}');
select public.test_assert((select status='disputed' from public.event_plans where id=current_setting('test.superseded_quote')::uuid),'old deposit cannot confirm a newly priced agreement');
select public.test_assert((select status='reconciliation_required' from public.payment_intents where idempotency_key='superseded-quote-payment'),'superseded quote payment is recorded for finance review');
