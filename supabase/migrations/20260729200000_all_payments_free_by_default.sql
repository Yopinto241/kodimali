alter table public.marketplace_settings
  alter column contact_payments_enabled set default false,
  alter column agent_listing_payments_enabled set default false,
  alter column chat_payments_enabled set default false,
  add column if not exists subscription_payments_enabled boolean not null default false,
  add column if not exists listing_boost_payments_enabled boolean not null default false;

-- The requested initial platform state is free. Future administrator changes
-- remain persisted in this single Supabase row across sessions and devices.
update public.marketplace_settings set
  contact_payments_enabled=false,
  agent_listing_payments_enabled=false,
  chat_payments_enabled=false,
  subscription_payments_enabled=false,
  listing_boost_payments_enabled=false,
  updated_at=now();

create or replace function public.contact_payments_enabled() returns boolean language sql stable security definer set search_path=public as $$
 select coalesce((select contact_payments_enabled from public.marketplace_settings where id=true),false)
$$;
create or replace function public.agent_listing_payments_enabled() returns boolean language sql stable security definer set search_path=public as $$
 select coalesce((select agent_listing_payments_enabled from public.marketplace_settings where id=true),false)
$$;
create or replace function public.chat_payments_enabled() returns boolean language sql stable security definer set search_path=public as $$
 select coalesce((select chat_payments_enabled from public.marketplace_settings where id=true),false)
$$;
create or replace function public.commercial_payment_enabled(p_product_type text) returns boolean language sql stable security definer set search_path=public as $$
 select coalesce((select case p_product_type when 'subscription' then subscription_payments_enabled when 'listing_boost' then listing_boost_payments_enabled else false end from public.marketplace_settings where id=true),false)
$$;
grant execute on function public.commercial_payment_enabled(text) to authenticated,service_role;
