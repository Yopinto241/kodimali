alter table public.marketplace_settings
  add column if not exists agent_listing_payments_enabled boolean not null default true;

create or replace function public.agent_listing_payments_enabled()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select agent_listing_payments_enabled from public.marketplace_settings where id = true), true)
$$;
revoke all on function public.agent_listing_payments_enabled() from public;
grant execute on function public.agent_listing_payments_enabled() to authenticated, service_role;

create table if not exists public.agent_listing_payments (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  agent_id uuid not null references public.agents(id) on delete cascade,
  order_reference text not null unique,
  payment_provider text not null default 'clickpesa',
  payment_status text not null default 'pending' check (payment_status in ('pending','processing','paid','failed','expired','cancelled')),
  requested_amount numeric(12,2) not null default 1000 check (requested_amount = 1000),
  requested_currency text not null default 'TZS',
  customer_phone_number text not null,
  provider_payment_id text,
  provider_payment_reference text,
  provider_channel text,
  status_message text,
  provider_response jsonb not null default '{}'::jsonb,
  webhook_payload jsonb not null default '{}'::jsonb,
  webhook_received_at timestamptz,
  reconciliation_status text,
  next_reconcile_at timestamptz,
  initiated_at timestamptz not null default timezone('utc', now()),
  paid_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (listing_id)
);
alter table public.agent_listing_payments enable row level security;
create policy agent_listing_payments_owner_select on public.agent_listing_payments
  for select to authenticated using (agent_id in (select id from public.agents where profile_id = auth.uid()));

create or replace function public.release_paid_agent_listing()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.payment_status = 'paid' and old.payment_status is distinct from 'paid' then
    update public.listings set status = 'active', published_at = coalesce(published_at, timezone('utc', now()))
    where id = new.listing_id and agent_id = new.agent_id and status = 'inactive' and removed_from_market_at is null;
  end if;
  return new;
end $$;
drop trigger if exists release_paid_agent_listing on public.agent_listing_payments;
create trigger release_paid_agent_listing after update of payment_status on public.agent_listing_payments
for each row execute function public.release_paid_agent_listing();

create or replace function public.enforce_agent_listing_payment_before_publish()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'active' and old.status is distinct from 'active'
     and public.agent_listing_payments_enabled()
     and not exists (
       select 1 from public.agent_listing_payments p
       where p.listing_id = new.id and p.agent_id = new.agent_id and p.payment_status = 'paid'
     ) then
    raise exception 'Agent listing payment is required before publication' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists enforce_agent_listing_payment_before_publish on public.listings;
create trigger enforce_agent_listing_payment_before_publish before update of status on public.listings
for each row execute function public.enforce_agent_listing_payment_before_publish();
