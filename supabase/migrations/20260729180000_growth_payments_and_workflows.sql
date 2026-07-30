create table if not exists public.agent_commercial_payments (
  id uuid primary key default gen_random_uuid(), agent_id uuid not null references public.agents(id) on delete cascade,
  product_type text not null check(product_type in ('subscription','listing_boost')),
  plan_id text references public.agent_subscription_plans(id), listing_boost_id uuid references public.listing_boosts(id),
  order_reference text not null unique, payment_status text not null default 'pending' check(payment_status in ('pending','processing','paid','failed','expired','cancelled')),
  requested_amount numeric(12,2) not null check(requested_amount>=0), requested_currency text not null default 'TZS', customer_phone_number text not null,
  provider_payment_id text, provider_payment_reference text, provider_channel text, provider_response jsonb not null default '{}'::jsonb,
  status_message text, paid_at timestamptz, failed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.agent_commercial_payments enable row level security;
create policy commercial_owner_read on public.agent_commercial_payments for select to authenticated using(public.is_admin() or agent_id=public.current_agent_id());
create policy commercial_admin on public.agent_commercial_payments for all to authenticated using(public.is_admin()) with check(public.is_admin());

create or replace function public.activate_agent_commercial_purchase()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_profile uuid;
begin
 if new.payment_status='paid' and old.payment_status is distinct from 'paid' then
  if new.product_type='subscription' then
   update public.agent_subscriptions set status='expired',updated_at=now() where agent_id=new.agent_id and status='active';
   insert into public.agent_subscriptions(agent_id,plan_id,status,starts_at,expires_at)
   values(new.agent_id,new.plan_id,'active',now(),now()+interval '30 days');
  elsif new.product_type='listing_boost' then
   update public.listing_boosts set status='active',starts_at=now(),ends_at=now()+make_interval(days=>duration_days),updated_at=now() where id=new.listing_boost_id and agent_id=new.agent_id;
  end if;
  select profile_id into v_profile from public.agents where id=new.agent_id;
  insert into public.payment_receipts(user_id,agent_id,payment_kind,source_payment_id,receipt_number,amount_tzs,status,metadata)
  values(v_profile,new.agent_id,new.product_type,new.id,'KDM-'||upper(substr(replace(new.id::text,'-',''),1,12)),new.requested_amount,'paid',jsonb_build_object('plan_id',new.plan_id,'listing_boost_id',new.listing_boost_id,'reference',new.order_reference)) on conflict do nothing;
 end if; return new;
end $$;
drop trigger if exists activate_commercial_purchase on public.agent_commercial_payments;
create trigger activate_commercial_purchase after update of payment_status on public.agent_commercial_payments for each row execute function public.activate_agent_commercial_purchase();

create or replace function public.admin_set_subscription_plan(p_agent_id uuid,p_plan_id text,p_months integer default 1)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Admin access required'; end if;
 update public.agent_subscriptions set status='expired',updated_at=now() where agent_id=p_agent_id and status='active';
 insert into public.agent_subscriptions(agent_id,plan_id,status,starts_at,expires_at) values(p_agent_id,p_plan_id,'active',now(),case when p_plan_id='free' then null else now()+make_interval(months=>greatest(1,p_months)) end);
 insert into public.audit_logs(actor_id,action,target_table,target_id,metadata) values(auth.uid(),'subscription_changed','agents',p_agent_id,jsonb_build_object('plan_id',p_plan_id));
end $$;
grant execute on function public.admin_set_subscription_plan(uuid,text,integer) to authenticated;

create or replace function public.expire_growth_products()
returns void language plpgsql security definer set search_path=public as $$
begin
 update public.agent_subscriptions set status='expired',updated_at=now() where status='active' and expires_at<=now();
 update public.listing_boosts set status='expired',updated_at=now() where status='active' and ends_at<=now();
end $$;
grant execute on function public.expire_growth_products() to service_role;
