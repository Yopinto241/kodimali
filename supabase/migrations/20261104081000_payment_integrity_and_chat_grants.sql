-- Preserve historical access and controls; never replay historical charges.
create table public.chat_entitlement_grants (
 payment_id uuid primary key references public.listing_chat_payments(id) on delete cascade,
 customer_id uuid not null, listing_id uuid not null, agent_id uuid not null,
 granted_at timestamptz not null, expires_at timestamptz not null,
 historical boolean not null default false
);
alter table public.chat_entitlement_grants enable row level security;
revoke all on public.chat_entitlement_grants from anon,authenticated;
grant all on public.chat_entitlement_grants to service_role;
-- Mark all previously successful receipts consumed, including earlier renewals.
-- Do not shorten any existing entitlement, or resurrect a revoked entitlement.
insert into public.chat_entitlement_grants(payment_id,customer_id,listing_id,agent_id,granted_at,expires_at,historical)
select p.id,p.customer_id,p.listing_id,p.agent_id,coalesce(p.paid_at,p.created_at),
 coalesce(a.expires_at,coalesce(p.paid_at,p.created_at)+interval '7 days'),true
from public.listing_chat_payments p left join public.listing_chat_access a
 on a.customer_id=p.customer_id and a.listing_id=p.listing_id and a.agent_id=p.agent_id
where p.payment_status='paid' on conflict do nothing;
-- Recover only missing, still-current access with the original paid date.
insert into public.listing_chat_access(listing_id,agent_id,customer_id,payment_id,access_source,starts_at,expires_at)
select distinct on (p.customer_id,p.listing_id,p.agent_id)
 p.listing_id,p.agent_id,p.customer_id,p.id,'paid',coalesce(p.paid_at,p.created_at),coalesce(p.paid_at,p.created_at)+interval '7 days'
from public.listing_chat_payments p where p.payment_status='paid'
 and coalesce(p.paid_at,p.created_at)+interval '7 days'>now()
order by p.customer_id,p.listing_id,p.agent_id,coalesce(p.paid_at,p.created_at) desc
on conflict(customer_id,listing_id,agent_id) do nothing;

create or replace function public.grant_listing_chat_access(p_payment_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare p public.listing_chat_payments; a public.listing_chat_access; expiry timestamptz;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
 select * into p from public.listing_chat_payments where id=p_payment_id and payment_status='paid' for update;
 if p.id is null then return; end if;
 -- Serializes distinct renewals for the same entitlement as well as replays.
 perform pg_advisory_xact_lock(hashtextextended(p.customer_id::text||p.listing_id::text||p.agent_id::text,0));
 if exists(select 1 from public.chat_entitlement_grants where payment_id=p.id) then return; end if;
 select * into a from public.listing_chat_access where customer_id=p.customer_id and listing_id=p.listing_id and agent_id=p.agent_id for update;
 if a.revoked_at is not null then
   insert into public.financial_reconciliation_cases(provider,provider_order_id,reason,currency,expected_amount_minor)
   values(p.payment_provider,p.provider_payment_id,'Paid chat renewal requires review because access was revoked',p.requested_currency,p.requested_amount);
   return;
 end if;
 expiry:=greatest(coalesce(a.expires_at,now()),now())+interval '7 days';
 insert into public.chat_entitlement_grants values(p.id,p.customer_id,p.listing_id,p.agent_id,now(),expiry,false);
 insert into public.listing_chat_access(listing_id,agent_id,customer_id,payment_id,access_source,starts_at,expires_at)
 values(p.listing_id,p.agent_id,p.customer_id,p.id,'paid',now(),expiry)
 on conflict(customer_id,listing_id,agent_id) do update set payment_id=excluded.payment_id,access_source='paid',starts_at=excluded.starts_at,expires_at=excluded.expires_at,updated_at=now();
end $$;
revoke all on function public.grant_listing_chat_access(uuid) from public,anon,authenticated;
grant execute on function public.grant_listing_chat_access(uuid) to service_role;
-- The existing release_paid_listing_chat trigger is the single grant path.

create table public.verified_payment_evidence (
 provider text not null, transaction_id text not null,
 payment_table text not null, payment_id uuid not null, provider_order_id text not null,
 amount numeric not null, currency text not null, verified_at timestamptz not null default now(),
 primary key(provider,transaction_id),unique(payment_table,payment_id)
);
alter table public.verified_payment_evidence enable row level security;
revoke all on public.verified_payment_evidence from anon,authenticated;
grant all on public.verified_payment_evidence to service_role;

-- Defense in depth for polling, webhook, expiry and legacy paths. Conflicting
-- final states remain final; callers inspect the persisted result, not a hint.
create or replace function public.protect_terminal_payment_state()
returns trigger language plpgsql set search_path=public as $$
declare old_status text; new_status text;
begin
 old_status:=to_jsonb(old)->>tg_argv[0]; new_status:=to_jsonb(new)->>tg_argv[0];
 if new_status='paid' and old_status is distinct from 'paid' and not exists(
   select 1 from public.verified_payment_evidence e where e.payment_table=tg_table_name and e.payment_id=(to_jsonb(new)->>'id')::uuid
 ) then raise exception 'Verified provider evidence is required before payment finalization'; end if;
 if old_status in ('paid','refunded','partially_refunded') and new_status is distinct from old_status then
   if old_status='paid' and new_status in ('refunded','partially_refunded') then return new; end if;
   new:=jsonb_populate_record(new,jsonb_build_object(tg_argv[0],old_status,
     'paid_at',to_jsonb(old)->'paid_at'));
 end if;
 return new;
end $$;
do $$ declare t text; col text; begin
 foreach t in array array['platform_payment_orders','listing_contact_payments','listing_chat_payments','agent_listing_payments','agent_commercial_payments'] loop
 col:=case when t='platform_payment_orders' then 'status' else 'payment_status' end;
 execute format('create trigger protect_terminal_payment before update on public.%I for each row execute function public.protect_terminal_payment_state(%L)',t,col);
 end loop;
end $$;

create or replace function public.apply_verified_payment_event(
 p_table text,p_payment_id uuid,p_provider text,p_status text,p_transaction_id text,p_payload jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb; current_status text; amount numeric; currency text; provider_order text;
 incoming_order text; incoming_amount numeric; incoming_currency text; v_reason text; evidence public.verified_payment_evidence;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
 if p_table not in ('platform_payment_orders','listing_contact_payments','listing_chat_payments','agent_listing_payments','agent_commercial_payments') then raise exception 'Unsupported payment table'; end if;
 if p_status not in ('pending','processing','paid','failed','cancelled','expired','refunded') then raise exception 'Unsupported payment state'; end if;
 execute format('select to_jsonb(t) from public.%I t where id=$1 for update',p_table) into r using p_payment_id;
 if r is null then raise exception 'Payment was not found'; end if;
 current_status:=coalesce(r->>'payment_status',r->>'status');
 amount:=coalesce(r->>'requested_amount',r->>'amount_tzs')::numeric;
 currency:=coalesce(r->>'requested_currency',r->>'currency');
 provider_order:=case when p_provider='clickpesa' then r->>'order_reference' else coalesce(r->>'provider_payment_id',r->>'provider_order_id') end;
 incoming_order:=p_payload->>'order_id'; incoming_currency:=upper(p_payload->>'currency');
 begin incoming_amount:=nullif(p_payload->>'amount','')::numeric; exception when others then incoming_amount:=null; end;
 if current_status in ('paid','refunded','partially_refunded') then
   if p_status=current_status or (current_status='paid' and p_status in ('pending','processing')) then
     return jsonb_build_object('status',current_status,'duplicate',true);
   end if;
   v_reason:='Contradictory provider event after terminal payment state: '||current_status||' -> '||p_status;
 elsif p_status='refunded' then v_reason:='Provider refund requires the approved refund/reconciliation workflow';
 elsif coalesce(r->>'payment_provider',r->>'provider') is distinct from p_provider then v_reason:='Provider does not match the recorded payment';
 elsif incoming_order is distinct from provider_order then v_reason:='Provider order does not match the recorded payment';
 elsif p_status='paid' and (nullif(trim(p_transaction_id),'') is null or incoming_amount is null or incoming_amount<>amount or incoming_currency is null or incoming_currency<>currency) then
   v_reason:='Missing or mismatched provider transaction, amount or currency evidence';
 end if;
 if v_reason is null and p_status='paid' then
   insert into public.verified_payment_evidence(provider,transaction_id,payment_table,payment_id,provider_order_id,amount,currency)
   values(p_provider,p_transaction_id,p_table,p_payment_id,provider_order,amount,currency) on conflict do nothing;
   select * into evidence from public.verified_payment_evidence where provider=p_provider and transaction_id=p_transaction_id;
   if evidence.payment_id is distinct from p_payment_id or evidence.payment_table is distinct from p_table then v_reason:='Provider transaction already belongs to another payment'; end if;
 end if;
 if v_reason is not null then
   if not exists(select from public.financial_reconciliation_cases where provider=p_provider and provider_order_id=provider_order and financial_reconciliation_cases.reason=v_reason and status in ('open','investigating')) then
     insert into public.financial_reconciliation_cases(provider,provider_order_id,provider_transaction_id,payment_intent_id,expected_amount_minor,reported_amount_minor,currency,reason)
     values(p_provider,provider_order,nullif(p_transaction_id,''),(r->>'payment_intent_id')::uuid,amount,incoming_amount,coalesce(incoming_currency,currency),v_reason);
   end if;
   if p_table='platform_payment_orders' and current_status not in ('paid','refunded','partially_refunded') then
     update public.platform_payment_orders set status='reconciliation_required',status_message=v_reason,updated_at=now() where id=p_payment_id;
     current_status:='reconciliation_required';
   end if;
   return jsonb_build_object('status',current_status,'reconciliationRequired',true);
 end if;
 if p_table='platform_payment_orders' then
   if p_status='paid' then
     perform public.finalize_platform_payment(p_payment_id,p_transaction_id,p_payload);
   else update public.platform_payment_orders set status=p_status,provider_response=p_payload,updated_at=now() where id=p_payment_id; end if;
 else
   execute format('update public.%I set payment_status=$1,provider_payment_reference=coalesce($2,provider_payment_reference),provider_response=$3,paid_at=case when $1=''paid'' then coalesce(paid_at,now()) else paid_at end,updated_at=now() where id=$4',p_table)
   using p_status,nullif(p_transaction_id,''),p_payload,p_payment_id;
 end if;
 if p_table='listing_contact_payments' and p_status='paid' then
   update public.listing_contact_payments set access_expires_at=coalesce(access_expires_at,paid_at+interval '24 hours') where id=p_payment_id;
 end if;
 return jsonb_build_object('status',p_status);
end $$;
revoke all on function public.apply_verified_payment_event(text,uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.apply_verified_payment_event(text,uuid,text,text,text,jsonb) to service_role;

alter function public.finalize_platform_payment(uuid,text,jsonb) rename to finalize_platform_payment_before_integrity;
revoke all on function public.finalize_platform_payment_before_integrity(uuid,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.finalize_platform_payment_before_events_repair(uuid,text,jsonb) from public,anon,authenticated,service_role;
create function public.finalize_platform_payment(p_order_id uuid,p_provider_transaction_id text,p_provider_payload jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare o public.platform_payment_orders;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
 select * into o from public.platform_payment_orders where id=p_order_id for update;
 if o.id is null then raise exception 'Payment was not found'; end if;
 if o.status in ('paid','refunded','partially_refunded') then return; end if;
 if not exists(select 1 from public.verified_payment_evidence e
   where e.payment_table='platform_payment_orders' and e.payment_id=o.id
     and e.provider=o.provider and e.provider_order_id=o.provider_order_id
     and e.transaction_id=p_provider_transaction_id and e.amount=o.amount_tzs and e.currency=o.currency
 ) then raise exception 'Verified provider evidence is required before payment finalization'; end if;
 perform public.finalize_platform_payment_before_integrity(p_order_id,p_provider_transaction_id,p_provider_payload);
end $$;
revoke all on function public.finalize_platform_payment(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.finalize_platform_payment(uuid,text,jsonb) to service_role;
notify pgrst,'reload schema';
