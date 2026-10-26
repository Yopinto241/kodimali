-- Unified, server-authoritative SonicPesa checkout for reservations and Events.
-- Existing contact/chat/commercial tables remain supported by the webhook.

alter table public.marketplace_settings
  add column if not exists booking_payments_enabled boolean not null default true,
  add column if not exists event_payments_enabled boolean not null default true,
  add column if not exists booking_reservation_fee_tzs integer not null default 10000 check (booking_reservation_fee_tzs >= 1000),
  add column if not exists event_deposit_percent integer not null default 30 check (event_deposit_percent between 1 and 100);

update public.marketplace_settings
set booking_payments_enabled = true,
    event_payments_enabled = true,
    contact_payments_enabled = true,
    chat_payments_enabled = true,
    subscription_payments_enabled = true,
    updated_at = now()
where id = true;

alter table public.agent_commercial_payments add column if not exists payment_provider text not null default 'sonicpesa';

create table if not exists public.platform_payment_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  purpose text not null check (purpose in ('booking_reservation','event_deposit','event_balance')),
  resource_id uuid not null,
  order_reference text not null unique,
  provider text not null default 'sonicpesa' check (provider in ('sonicpesa')),
  provider_order_id text unique,
  provider_transaction_id text,
  amount_tzs numeric(14,2) not null check (amount_tzs >= 1000),
  currency text not null default 'TZS' check (currency = 'TZS'),
  customer_phone_number text not null,
  status text not null default 'pending' check (status in ('pending','processing','paid','failed','cancelled','expired','refundable','refunded','disputed')),
  provider_response jsonb not null default '{}'::jsonb,
  status_message text,
  paid_at timestamptz,
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists platform_payment_orders_user_created_idx on public.platform_payment_orders(user_id, created_at desc);
create index if not exists platform_payment_orders_provider_order_idx on public.platform_payment_orders(provider_order_id) where provider_order_id is not null;
create unique index if not exists platform_payment_orders_one_open_idx on public.platform_payment_orders(purpose,resource_id) where status in ('pending','processing','paid');
alter table public.platform_payment_orders enable row level security;
create policy platform_payment_orders_owner_read on public.platform_payment_orders for select to authenticated
using (user_id = auth.uid() or public.is_admin());

do $$ declare constraint_name text; begin
  for constraint_name in
    select c.conname from pg_constraint c
    where c.conrelid='public.event_payment_obligations'::regclass
      and c.contype='c'
      and pg_get_constraintdef(c.oid) ilike '%collection_enabled%false%'
  loop execute format('alter table public.event_payment_obligations drop constraint %I',constraint_name); end loop;
end $$;
alter table public.event_payment_obligations alter column collection_enabled set default true;
alter table public.event_payment_obligations add column if not exists payment_order_id uuid references public.platform_payment_orders(id) on delete set null;

alter table public.event_plans drop constraint if exists event_plans_status_check;
alter table public.event_plans add constraint event_plans_status_check check(status in('draft','quote_requested','provider_review','partially_confirmed','fully_confirmed','agreement_pending','payment_pending','confirmed','in_progress','completed','cancelled','disputed'));

alter table public.booking_payment_transactions drop constraint if exists booking_payment_transactions_status_check;
alter table public.booking_payment_transactions add constraint booking_payment_transactions_status_check
check(status in('created','pending','processing','authorized','paid','failed','cancelled','expired','refundable','refunded','disputed'));
alter table public.booking_payment_transactions
  add column if not exists payment_order_id uuid references public.platform_payment_orders(id) on delete set null,
  add column if not exists paid_at timestamptz,
  add column if not exists provider_payload jsonb not null default '{}'::jsonb;

create or replace function public.payment_feature_enabled(p_purpose text)
returns boolean language sql stable security definer set search_path=public as $$
 select coalesce((select case
   when p_purpose='booking_reservation' then booking_payments_enabled
   when p_purpose in ('event_deposit','event_balance') then event_payments_enabled
   else false end from public.marketplace_settings where id=true),false)
$$;
revoke all on function public.payment_feature_enabled(text) from public;
grant execute on function public.payment_feature_enabled(text) to authenticated,service_role;

create or replace function public.prepare_booking_for_payment(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare b public.booking_requests; amount numeric; asset uuid;
begin
 select * into b from public.booking_requests where id=p_booking_id and customer_id=auth.uid() for update;
 if b.id is null then raise exception 'Booking was not found'; end if;
 if b.requested_start_at is null or b.requested_end_at is null or b.requested_end_at<=b.requested_start_at then raise exception 'Valid booking dates are required'; end if;
 if b.owner_approval_status not in ('not_required','approved') then raise exception 'Owner approval is required before payment'; end if;
 select asset_id into asset from public.listings where id=b.listing_id;
 if asset is null then raise exception 'This listing is not connected to reservable inventory'; end if;
 if exists(select 1 from public.asset_reservations r where r.asset_id=asset and r.status in('held','confirmed') and r.occupied_period&&tstzrange(b.requested_start_at,b.requested_end_at,'[)')) then raise exception 'The selected period is no longer available' using errcode='23P01'; end if;
 select coalesce(nullif((p.fee_configuration->>'reservation_fee_tzs')::numeric,0),s.booking_reservation_fee_tzs)
 into amount from public.marketplace_settings s left join public.booking_policies p on p.id=b.policy_id where s.id=true;
 update public.booking_requests set booking_kind='reservation',policy_accepted_at=coalesce(policy_accepted_at,now()),payment_expires_at=now()+interval '30 minutes',updated_at=now() where id=b.id;
 return jsonb_build_object('amount_tzs',amount,'customer_id',b.customer_id,'asset_id',asset);
end $$;
revoke all on function public.prepare_booking_for_payment(uuid) from public;
grant execute on function public.prepare_booking_for_payment(uuid) to authenticated;

create or replace function public.prepare_event_for_payment(p_plan_id uuid,p_kind text default 'event_deposit')
returns jsonb language plpgsql security definer set search_path=public as $$
declare p public.event_plans;q public.event_quote_revisions;amount numeric;percent integer;
begin
 if p_kind not in ('event_deposit','event_balance') then raise exception 'Unsupported event payment kind'; end if;
 select * into p from public.event_plans where id=p_plan_id and customer_id=auth.uid() for update;
 if p.id is null then raise exception 'Event plan was not found'; end if;
 select * into q from public.event_quote_revisions where id=p.accepted_quote_revision_id and status='accepted';
 if q.id is null then raise exception 'Accept a valid quotation before payment'; end if;
 if not exists(select 1 from public.event_agreements a where a.plan_id=p.id and a.status='accepted') then raise exception 'Accept the event agreement before payment'; end if;
 select event_deposit_percent into percent from public.marketplace_settings where id=true;
 amount:=case when p_kind='event_deposit' then greatest(1000,ceil(q.total_tzs*percent/100.0)) else greatest(0,q.total_tzs-coalesce((select sum(o.amount_tzs) from public.event_payment_obligations o where o.plan_id=p.id and o.status='paid' and o.kind='deposit'),0)) end;
 if amount<1000 then raise exception 'No payable event balance remains'; end if;
 update public.event_plans set status='payment_pending',updated_at=now() where id=p.id and status in('agreement_pending','payment_pending');
 return jsonb_build_object('amount_tzs',amount,'customer_id',p.customer_id,'quote_total_tzs',q.total_tzs);
end $$;
revoke all on function public.prepare_event_for_payment(uuid,text) from public;
grant execute on function public.prepare_event_for_payment(uuid,text) to authenticated;

create or replace function public.finalize_platform_payment(p_order_id uuid,p_provider_transaction_id text,p_provider_payload jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare o public.platform_payment_orders; b public.booking_requests; asset uuid; obligation_kind text;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required'; end if;
 select * into o from public.platform_payment_orders where id=p_order_id for update;
 if o.id is null then raise exception 'Payment order not found'; end if;
 if o.status='paid' then return; end if;
 update public.platform_payment_orders set status='paid',provider_transaction_id=nullif(trim(p_provider_transaction_id),''),provider_response=coalesce(p_provider_payload,'{}'),paid_at=now(),updated_at=now() where id=o.id;
 if o.purpose='booking_reservation' then
  select * into b from public.booking_requests where id=o.resource_id for update;
  if b.customer_id<>o.user_id then raise exception 'Booking payment owner mismatch'; end if;
  select asset_id into asset from public.listings where id=b.listing_id;
  insert into public.booking_payment_transactions(booking_request_id,provider,provider_reference,kind,amount_tzs,status,verified_at,paid_at,payment_order_id,provider_payload)
  values(b.id,'sonicpesa',coalesce(nullif(trim(p_provider_transaction_id),''),o.provider_order_id),'reservation',o.amount_tzs,'paid',now(),now(),o.id,coalesce(p_provider_payload,'{}')) on conflict(provider,provider_reference) do nothing;
  insert into public.asset_reservations(asset_id,booking_request_id,occupied_period,status,created_by)
  values(asset,b.id,tstzrange(b.requested_start_at,b.requested_end_at,'[)'),'confirmed',o.user_id)
  on conflict(booking_request_id) do update set status='confirmed',updated_at=now();
  update public.booking_requests set booking_status='confirmed',updated_at=now() where id=b.id;
 elsif o.purpose in ('event_deposit','event_balance') then
  obligation_kind:=case when o.purpose='event_deposit' then 'deposit' else 'balance' end;
  insert into public.event_payment_obligations(plan_id,kind,amount_tzs,due_at,status,collection_enabled,external_reference,payment_order_id)
  values(o.resource_id,obligation_kind,o.amount_tzs,now(),'paid',true,coalesce(nullif(trim(p_provider_transaction_id),''),o.provider_order_id),o.id);
  if o.purpose='event_deposit' then
   update public.event_equipment_allocations x set status='confirmed',expires_at=null from public.event_plan_items i where i.id=x.plan_item_id and i.plan_id=o.resource_id and x.status='held';
   update public.event_service_bookings x set status='confirmed',expires_at=null from public.event_plan_items i where i.id=x.plan_item_id and i.plan_id=o.resource_id and x.status='held';
   update public.event_plans set status='confirmed',updated_at=now() where id=o.resource_id;
   update public.event_individual_bookings set payment_status='paid',status='confirmed',updated_at=now() where plan_id=o.resource_id;
  end if;
  insert into public.event_audit_log(plan_id,actor_id,action,details) values(o.resource_id,o.user_id,'payment.confirmed',jsonb_build_object('payment_order_id',o.id,'purpose',o.purpose,'amount_tzs',o.amount_tzs));
 end if;
end $$;
revoke all on function public.finalize_platform_payment(uuid,text,jsonb) from public;
grant execute on function public.finalize_platform_payment(uuid,text,jsonb) to service_role;

create or replace function public.expire_growth_products()
returns void language plpgsql security definer set search_path=public as $$
begin
 update public.agent_subscriptions set status='expired',updated_at=now() where status='active' and expires_at is not null and expires_at<=now();
 update public.listing_boosts set status='expired',updated_at=now() where status='active' and ends_at is not null and ends_at<=now();
 update public.platform_payment_orders set status='expired',updated_at=now() where status in('pending','processing') and expires_at<=now();
end $$;
revoke all on function public.expire_growth_products() from public;
grant execute on function public.expire_growth_products() to service_role;

do $$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  perform cron.unschedule(jobid) from cron.job where jobname='expire-growth-products';
  perform cron.schedule('expire-growth-products','*/10 * * * *','select public.expire_growth_products()');
 end if;
end $$;

-- Agreement acceptance now waits for verified payment instead of confirming inventory for free.
create or replace function public.accept_event_agreement(p_agreement_id uuid)returns public.event_plans language plpgsql security definer set search_path=public as $$
declare a public.event_agreements;p public.event_plans;
begin
 select * into a from public.event_agreements where id=p_agreement_id for update;
 select * into p from public.event_plans where id=a.plan_id and customer_id=auth.uid() for update;
 if p.id is null or a.status<>'sent' then raise exception 'Event agreement is unavailable';end if;
 update public.event_agreements set status='accepted',accepted_by=auth.uid(),accepted_at=now() where id=a.id;
 update public.event_plans set status='payment_pending',updated_at=now() where id=p.id returning * into p;
 update public.event_individual_bookings set payment_status='pending',updated_at=now() where plan_id=p.id;
 insert into public.event_audit_log(plan_id,actor_id,action,details)values(p.id,auth.uid(),'agreement.accepted',jsonb_build_object('agreement_id',a.id,'payment_required',true));return p;
end$$;
