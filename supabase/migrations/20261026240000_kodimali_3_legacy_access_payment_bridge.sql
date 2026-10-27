-- KODIMALI 3.0 compatibility bridge for existing contact/chat products.
-- Existing APIs and entitlement tables remain authoritative for delivery while
-- every payment is mirrored into the unified typed financial core.

create unique index if not exists listing_chat_one_open_payment_idx
on public.listing_chat_payments(customer_id, listing_id)
where payment_status in ('pending','processing');

create or replace function public.sync_legacy_access_payment_intent()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product text;
  v_customer_id uuid;
  v_resource_id uuid;
  v_amount numeric;
  v_currency text;
  v_provider text;
  v_order_id text;
  v_transaction_id text;
  v_legacy_status text;
  v_created_at timestamptz;
  v_status text;
begin
  if tg_table_name = 'listing_chat_payments' then
    v_product := 'paid_chat_unlock';
    v_customer_id := new.customer_id;
  elsif tg_table_name = 'listing_contact_payments' then
    v_product := 'contact_unlock';
    v_customer_id := null;
  else
    raise exception 'Unsupported legacy access payment table';
  end if;

  v_resource_id := new.listing_id;
  v_amount := new.requested_amount;
  v_currency := new.requested_currency;
  v_provider := new.payment_provider;
  v_order_id := new.provider_payment_id;
  v_transaction_id := new.provider_payment_reference;
  v_legacy_status := new.payment_status;
  v_created_at := new.created_at;
  v_status := case v_legacy_status
    when 'pending' then 'awaiting_payment'
    when 'processing' then 'processing'
    when 'paid' then 'verified_paid'
    when 'expired' then 'expired'
    else 'failed'
  end;

  -- Preserve migration/webhook availability if historical legacy rows reused a
  -- provider reference. The duplicate remains visible in legacy reconciliation
  -- instead of violating the unified transaction identity constraint.
  if v_transaction_id is not null and exists (
    select 1 from public.payment_intents i
    where i.provider = v_provider
      and i.provider_transaction_id = v_transaction_id
      and i.idempotency_key <> 'legacy:' || tg_table_name || ':' || new.id::text
  ) then
    v_transaction_id := null;
  end if;

  insert into public.payment_intents(
    customer_id, product, resource_type, resource_id, amount_minor, currency,
    status, idempotency_key, provider, provider_order_id,
    provider_transaction_id, metadata, verified_at, created_at, updated_at
  ) values (
    v_customer_id, v_product, 'listing', v_resource_id,
    round(v_amount)::bigint, upper(v_currency), v_status,
    'legacy:' || tg_table_name || ':' || new.id::text,
    v_provider, v_order_id, v_transaction_id,
    jsonb_build_object(
      'legacy_table', tg_table_name,
      'legacy_payment_id', new.id,
      'order_reference', new.order_reference
    ),
    case when v_status = 'verified_paid' then coalesce(new.paid_at, now()) else null end,
    v_created_at, now()
  )
  on conflict(idempotency_key) do update set
    status = excluded.status,
    provider = excluded.provider,
    provider_order_id = excluded.provider_order_id,
    provider_transaction_id = excluded.provider_transaction_id,
    verified_at = coalesce(public.payment_intents.verified_at, excluded.verified_at),
    updated_at = now();

  return new;
end;
$$;

drop trigger if exists sync_chat_payment_intent on public.listing_chat_payments;
create trigger sync_chat_payment_intent
after insert or update of payment_status, provider_payment_id, provider_payment_reference
on public.listing_chat_payments
for each row execute function public.sync_legacy_access_payment_intent();

drop trigger if exists sync_contact_payment_intent on public.listing_contact_payments;
create trigger sync_contact_payment_intent
after insert or update of payment_status, provider_payment_id, provider_payment_reference
on public.listing_contact_payments
for each row execute function public.sync_legacy_access_payment_intent();

insert into public.payment_intents(
  customer_id, product, resource_type, resource_id, amount_minor, currency,
  status, idempotency_key, provider, provider_order_id,
  provider_transaction_id, metadata, verified_at, created_at, updated_at
)
select
  p.customer_id, 'paid_chat_unlock', 'listing', p.listing_id,
  round(p.requested_amount)::bigint, upper(p.requested_currency),
  case p.payment_status when 'pending' then 'awaiting_payment' when 'processing' then 'processing' when 'paid' then 'verified_paid' when 'expired' then 'expired' else 'failed' end,
  'legacy:listing_chat_payments:' || p.id::text,
  p.payment_provider, p.provider_payment_id, p.provider_payment_reference,
  jsonb_build_object('legacy_table','listing_chat_payments','legacy_payment_id',p.id,'order_reference',p.order_reference),
  case when p.payment_status='paid' then coalesce(p.paid_at,p.updated_at) end,
  p.created_at, p.updated_at
from public.listing_chat_payments p
on conflict do nothing;

insert into public.payment_intents(
  customer_id, product, resource_type, resource_id, amount_minor, currency,
  status, idempotency_key, provider, provider_order_id,
  provider_transaction_id, metadata, verified_at, created_at, updated_at
)
select
  null, 'contact_unlock', 'listing', p.listing_id,
  round(p.requested_amount)::bigint, upper(p.requested_currency),
  case p.payment_status when 'pending' then 'awaiting_payment' when 'processing' then 'processing' when 'paid' then 'verified_paid' when 'expired' then 'expired' else 'failed' end,
  'legacy:listing_contact_payments:' || p.id::text,
  p.payment_provider, p.provider_payment_id, p.provider_payment_reference,
  jsonb_build_object('legacy_table','listing_contact_payments','legacy_payment_id',p.id,'order_reference',p.order_reference),
  case when p.payment_status='paid' then coalesce(p.paid_at,p.updated_at) end,
  p.created_at, p.updated_at
from public.listing_contact_payments p
on conflict do nothing;

revoke all on function public.sync_legacy_access_payment_intent() from public, anon, authenticated;

comment on function public.sync_legacy_access_payment_intent() is
'Mirrors existing paid chat and contact unlock payments into typed payment intents without replacing entitlement delivery.';
