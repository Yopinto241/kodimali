-- KODIMALI 3.0: keep checkout simple for customers while making the invisible
-- inventory-payment hold configurable and bounded server-side.

alter table public.booking_configurations
  add column if not exists hold_duration_minutes smallint not null default 30
  check(hold_duration_minutes between 5 and 60);

create or replace function public.resolve_booking_hold_minutes(
  p_listing_id uuid default null,
  p_flag_key text default null
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_minutes integer; v_configured text;
begin
  if p_listing_id is not null then
    select hold_duration_minutes into v_minutes
    from public.booking_configurations where listing_id=p_listing_id;
  end if;
  if v_minutes is null and p_flag_key is not null then
    select configuration->>'hold_minutes' into v_configured
    from public.kodimali_feature_flags where key=p_flag_key;
    if coalesce(v_configured,'') ~ '^[0-9]+$' then v_minutes:=v_configured::integer; end if;
  end if;
  return greatest(5,least(60,coalesce(v_minutes,30)));
end;
$$;

revoke all on function public.resolve_booking_hold_minutes(uuid,text) from public;
grant execute on function public.resolve_booking_hold_minutes(uuid,text)
to anon,authenticated,service_role;

create or replace function public.prepare_booking_payment_intent(
  p_booking_id uuid,
  p_product text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  b public.booking_requests;
  s public.booking_terms_snapshots;
  amount bigint;
  paid_deposit bigint;
  paid_balance bigint;
  intent public.payment_intents;
  asset uuid;
  listing uuid;
  hold_until timestamptz;
  hold_minutes integer;
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
  select l.asset_id,l.id into asset,listing from public.listings l where l.id=b.listing_id;
  if asset is null then raise exception 'Listing is not connected to reservable inventory'; end if;
  if p_product='booking_deposit' then
    update public.asset_reservations r set status='expired',updated_at=now() from public.booking_requests x where r.booking_request_id=x.id and r.status='held' and x.payment_expires_at<=now();
    if exists(select 1 from public.asset_reservations r where r.asset_id=asset and r.booking_request_id<>b.id and r.status in ('held','confirmed') and r.occupied_period&&tstzrange(b.requested_start_at,b.requested_end_at,'[)')) then raise exception 'The selected period is no longer available' using errcode='23P01'; end if;
    hold_minutes:=public.resolve_booking_hold_minutes(listing,'booking_deposit_payments');
    hold_until:=now()+make_interval(mins=>hold_minutes);
    insert into public.asset_reservations(asset_id,booking_request_id,occupied_period,status,created_by) values(asset,b.id,tstzrange(b.requested_start_at,b.requested_end_at,'[)'),'held',auth.uid())
    on conflict(booking_request_id) do update set occupied_period=excluded.occupied_period,status=case when public.asset_reservations.status='confirmed' then 'confirmed' else 'held' end,updated_at=now();
    update public.booking_requests set booking_status='reserved',payment_expires_at=hold_until,payment_ready_at=coalesce(payment_ready_at,now()),updated_at=now() where id=b.id;
  end if;
  insert into public.payment_intents(customer_id,product,resource_type,resource_id,amount_minor,idempotency_key,agreement_snapshot_id,status,expires_at,metadata)
  values(auth.uid(),p_product,'booking_request',b.id,amount,trim(p_idempotency_key),s.id,'awaiting_payment',case when p_product='booking_deposit' then hold_until else s.balance_due_at end,jsonb_build_object('booking_reference',b.request_reference,'terms_version',s.version,'hold_minutes',hold_minutes))
  on conflict(idempotency_key) do update set updated_at=now() returning * into intent;
  if intent.customer_id<>auth.uid() or intent.resource_id<>b.id or intent.product<>p_product or intent.amount_minor<>amount then raise exception 'Idempotency key belongs to a different payment request'; end if;
  return jsonb_build_object('payment_intent_id',intent.id,'amount_minor',intent.amount_minor,'currency',intent.currency,'product',intent.product,'expires_at',intent.expires_at,'hold_expires_at',hold_until);
end;
$$;

create or replace function public.prepare_event_payment_intent(
  p_plan_id uuid,
  p_product text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan public.event_plans;
  v_quote public.event_quote_revisions;
  v_agreement public.event_agreements;
  v_deposit bigint;
  v_balance bigint;
  v_paid_deposit bigint;
  v_paid_balance bigint;
  v_amount bigint;
  v_intent public.payment_intents;
  v_hold_minutes integer;
begin
  if p_product not in ('event_deposit','event_balance') then raise exception 'Unsupported event payment product'; end if;
  if not public.kodimali_feature_enabled(case when p_product='event_deposit' then 'event_deposit_payments' else 'event_balance_payments' end) then raise exception 'This event payment product is not enabled'; end if;
  if nullif(trim(p_idempotency_key),'') is null then raise exception 'Idempotency key is required'; end if;
  select * into v_plan from public.event_plans where id=p_plan_id and customer_id=auth.uid() for update;
  if v_plan.id is null then raise exception 'Event plan was not found'; end if;
  select * into v_quote from public.event_quote_revisions where id=v_plan.accepted_quote_revision_id and status='accepted';
  if v_quote.id is null then raise exception 'Accept a valid quotation before payment'; end if;
  select * into v_agreement from public.event_agreements where plan_id=v_plan.id and status='accepted' order by version desc limit 1;
  if v_agreement.id is null then raise exception 'Accept the event agreement before payment'; end if;
  select deposit_minor,balance_minor into v_deposit,v_balance from public.calculate_booking_split(round(v_quote.total_tzs)::bigint,25);
  select coalesce(sum(amount_minor),0) into v_paid_deposit from public.payment_intents where resource_type='event_plan' and resource_id=v_plan.id and product='event_deposit' and status='verified_paid';
  select coalesce(sum(amount_minor),0) into v_paid_balance from public.payment_intents where resource_type='event_plan' and resource_id=v_plan.id and product='event_balance' and status='verified_paid';
  v_amount:=case when p_product='event_deposit' then greatest(0,v_deposit-v_paid_deposit) else greatest(0,v_balance-v_paid_balance) end;
  if p_product='event_balance' and v_paid_deposit<v_deposit then raise exception 'The event deposit must be verified first'; end if;
  if v_amount<=0 then raise exception 'No payable amount remains for this event payment'; end if;
  v_hold_minutes:=public.resolve_booking_hold_minutes(null,case when p_product='event_deposit' then 'event_deposit_payments' else 'event_balance_payments' end);
  insert into public.payment_intents(customer_id,product,resource_type,resource_id,amount_minor,currency,status,idempotency_key,metadata,expires_at)
  values(auth.uid(),p_product,'event_plan',v_plan.id,v_amount,'TZS','awaiting_payment',trim(p_idempotency_key),
    jsonb_build_object('event_reference',v_plan.reference,'quote_revision_id',v_quote.id,'quote_revision',v_quote.revision,'agreement_id',v_agreement.id,'agreement_version',v_agreement.version,'agreed_total_minor',round(v_quote.total_tzs)::bigint,'deposit_percent',25,'hold_minutes',v_hold_minutes),
    now()+make_interval(mins=>v_hold_minutes))
  on conflict(idempotency_key) do update set updated_at=now() returning * into v_intent;
  if v_intent.customer_id<>auth.uid() or v_intent.resource_id<>v_plan.id or v_intent.product<>p_product or v_intent.amount_minor<>v_amount then raise exception 'Idempotency key belongs to a different payment request'; end if;
  update public.event_plans set status='payment_pending',updated_at=now() where id=v_plan.id and status in ('agreement_pending','payment_pending');
  return jsonb_build_object('payment_intent_id',v_intent.id,'amount_minor',v_intent.amount_minor,'currency',v_intent.currency,'product',v_intent.product,'expires_at',v_intent.expires_at,'agreed_total_minor',round(v_quote.total_tzs)::bigint,'deposit_minor',v_deposit,'balance_minor',v_balance);
end;
$$;

comment on column public.booking_configurations.hold_duration_minutes is
'Invisible checkout inventory lock duration. It prevents double-booking and is not a customer workflow step.';
comment on function public.resolve_booking_hold_minutes(uuid,text) is
'Returns a bounded 5–60 minute inventory-payment hold, defaulting to 30.';

