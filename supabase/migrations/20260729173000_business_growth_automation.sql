-- Operational automation for plans, wallets, receipts and risk monitoring.

create unique index if not exists idx_receipts_source
  on public.payment_receipts(payment_kind, source_payment_id);

create or replace function public.initialize_agent_business_account()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.agent_wallets(agent_id) values(new.id) on conflict do nothing;
  insert into public.agent_subscriptions(agent_id,plan_id,status)
  values(new.id,'free','active') on conflict do nothing;
  return new;
end $$;
drop trigger if exists initialize_agent_business_account on public.agents;
create trigger initialize_agent_business_account after insert on public.agents
for each row execute function public.initialize_agent_business_account();
insert into public.agent_wallets(agent_id) select id from public.agents on conflict do nothing;
insert into public.agent_subscriptions(agent_id,plan_id,status)
select a.id,'free','active' from public.agents a
where not exists(select 1 from public.agent_subscriptions s where s.agent_id=a.id and s.status='active');

create or replace function public.receipt_for_agent_listing_payment()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_user uuid;
begin
  if new.payment_status='paid' and old.payment_status is distinct from 'paid' then
    select profile_id into v_user from public.agents where id=new.agent_id;
    insert into public.payment_receipts(user_id,agent_id,payment_kind,source_payment_id,receipt_number,amount_tzs,status,metadata)
    values(v_user,new.agent_id,'listing_publication',new.id,'KDM-'||upper(substr(replace(new.id::text,'-',''),1,12)),new.requested_amount,'paid',jsonb_build_object('listing_id',new.listing_id,'reference',new.order_reference)) on conflict do nothing;
  end if; return new;
end $$;
drop trigger if exists business_receipt_agent_listing on public.agent_listing_payments;
create trigger business_receipt_agent_listing after update of payment_status on public.agent_listing_payments for each row execute function public.receipt_for_agent_listing_payment();

create or replace function public.receipt_for_chat_payment()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.payment_status='paid' and old.payment_status is distinct from 'paid' then
    insert into public.payment_receipts(user_id,agent_id,payment_kind,source_payment_id,receipt_number,amount_tzs,status,metadata)
    values(new.customer_id,new.agent_id,'chat_access',new.id,'KDM-'||upper(substr(replace(new.id::text,'-',''),1,12)),new.requested_amount,'paid',jsonb_build_object('listing_id',new.listing_id,'reference',new.order_reference)) on conflict do nothing;
  end if; return new;
end $$;
drop trigger if exists business_receipt_chat on public.listing_chat_payments;
create trigger business_receipt_chat after update of payment_status on public.listing_chat_payments for each row execute function public.receipt_for_chat_payment();

create or replace function public.flag_duplicate_listing()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_match uuid;
begin
  select l.id into v_match from public.listings l where l.id<>new.id and l.agent_id=new.agent_id
    and lower(trim(l.title))=lower(trim(new.title)) and l.location_id=new.location_id
    and l.created_at>now()-interval '30 days' limit 1;
  if v_match is not null then
    insert into public.platform_risk_flags(entity_type,entity_id,risk_type,severity,reason,evidence)
    values('listing',new.id,'possible_duplicate','medium','A similar listing was posted by this agent in the last 30 days',jsonb_build_object('matching_listing_id',v_match));
  end if;
  return new;
end $$;
drop trigger if exists detect_duplicate_listing on public.listings;
create trigger detect_duplicate_listing after insert on public.listings for each row execute function public.flag_duplicate_listing();

create or replace function public.get_admin_growth_operations()
returns jsonb language sql stable security definer set search_path=public as $$
select case when public.is_admin() then jsonb_build_object(
 'subscriptions',(select count(*) from public.agent_subscriptions where status='active'),
 'active_boosts',(select count(*) from public.listing_boosts where status='active' and ends_at>now()),
 'pending_boosts',(select count(*) from public.listing_boosts where status='pending'),
 'open_refunds',(select count(*) from public.payment_refunds where status in ('requested','approved','processing')),
 'open_risks',(select count(*) from public.platform_risk_flags where status in ('open','reviewing')),
 'receipts',(select count(*) from public.payment_receipts)
) else '{}'::jsonb end $$;
grant execute on function public.get_admin_growth_operations() to authenticated;
