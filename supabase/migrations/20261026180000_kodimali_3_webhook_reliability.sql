-- KODIMALI 3.0 phase 3: retry-safe webhook inbox and reconciliation state.

alter table public.payment_webhook_events
  add column if not exists processing_status text not null default 'received',
  add column if not exists attempt_count integer not null default 0,
  add column if not exists last_attempt_at timestamptz;

do $$ declare c text; begin
 for c in select conname from pg_constraint where conrelid='public.payment_webhook_events'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%processing_status%'
 loop execute format('alter table public.payment_webhook_events drop constraint %I',c); end loop;
 alter table public.payment_webhook_events add constraint payment_webhook_events_processing_status_check
 check(processing_status in ('received','processing','processed','failed','reconciliation_required'));
end $$;

do $$ declare c text; begin
 for c in select conname from pg_constraint where conrelid='public.platform_payment_orders'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%status%'
 loop execute format('alter table public.platform_payment_orders drop constraint %I',c); end loop;
 alter table public.platform_payment_orders add constraint platform_payment_orders_status_check
 check(status in ('pending','processing','paid','failed','cancelled','expired','refundable','refunded','disputed','reconciliation_required'));
end $$;

create unique index if not exists platform_payment_orders_provider_transaction_idx
on public.platform_payment_orders(provider_transaction_id) where provider_transaction_id is not null;

create or replace function public.claim_payment_webhook_event(
 p_provider text,p_provider_event_id text,p_payload_digest text,p_signature_verified boolean
) returns boolean language plpgsql security definer set search_path=public as $$
declare r public.payment_webhook_events;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required'; end if;
 insert into public.payment_webhook_events(provider,provider_event_id,payload_digest,signature_verified,processing_status,attempt_count,last_attempt_at)
 values(p_provider,p_provider_event_id,p_payload_digest,p_signature_verified,'processing',1,now())
 on conflict(provider,provider_event_id) do nothing returning * into r;
 if r.id is not null then return true; end if;
 select * into r from public.payment_webhook_events where provider=p_provider and provider_event_id=p_provider_event_id for update;
 if r.processed_at is not null or r.processing_status='processed' then return false; end if;
 if r.processing_status='processing' and r.last_attempt_at>now()-interval '5 minutes' then return false; end if;
 update public.payment_webhook_events set processing_status='processing',attempt_count=attempt_count+1,last_attempt_at=now(),processing_error=null where id=r.id;
 return true;
end $$;
revoke all on function public.claim_payment_webhook_event(text,text,text,boolean) from public;
grant execute on function public.claim_payment_webhook_event(text,text,text,boolean) to service_role;

create or replace function public.finish_payment_webhook_event(p_provider text,p_provider_event_id text,p_status text,p_error text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.role()<>'service_role' then raise exception 'Service role required'; end if;
 if p_status not in ('processed','failed','reconciliation_required') then raise exception 'Invalid webhook processing status'; end if;
 update public.payment_webhook_events set processing_status=p_status,processing_error=nullif(trim(p_error),''),processed_at=case when p_status='processed' then now() else null end where provider=p_provider and provider_event_id=p_provider_event_id;
end $$;
revoke all on function public.finish_payment_webhook_event(text,text,text,text) from public;
grant execute on function public.finish_payment_webhook_event(text,text,text,text) to service_role;

comment on function public.claim_payment_webhook_event(text,text,text,boolean) is 'Claims new or safely retryable webhook events; processed and concurrently active events are not re-run.';
