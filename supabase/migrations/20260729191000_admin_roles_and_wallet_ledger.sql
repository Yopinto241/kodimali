create table if not exists public.admin_role_definitions(
 id text primary key, name text not null, description text not null, permissions jsonb not null default '[]'::jsonb,
 rank integer not null, is_active boolean not null default true, created_at timestamptz not null default now()
);
insert into public.admin_role_definitions(id,name,description,permissions,rank) values
('super_admin','Super Admin','Full platform control including assigning every administrative role.','["*"]',100),
('operations_admin','Operations Admin','Marketplace health, booking operations and daily escalations.','["dashboard.view","bookings.manage","health.view"]',80),
('finance_admin','Finance Admin','Payments, subscriptions, wallets, receipts and refunds.','["payments.manage","refunds.manage","wallets.manage","subscriptions.manage"]',80),
('agent_manager','Agent Manager','Agent verification, activation, assignments and performance.','["agents.manage","agent_roles.manage","agent_performance.view"]',70),
('listing_moderator','Listing Moderator','Listing approval, duplicate review, reports and fraud flags.','["listings.manage","reports.manage","risk.manage"]',60),
('support_admin','Customer Support','Users, conversations, requests and dispute follow-up.','["users.view","bookings.manage","support.manage"]',50),
('marketing_admin','Marketing Admin','Promotions, featured listings, categories and campaigns.','["promotions.manage","boosts.manage","analytics.view"]',50),
('analyst','Business Analyst','Read-only analytics, revenue and marketplace reporting.','["dashboard.view","analytics.view","payments.view"]',20)
on conflict(id) do update set name=excluded.name,description=excluded.description,permissions=excluded.permissions,rank=excluded.rank;

create table if not exists public.admin_role_assignments(
 user_id uuid not null references public.profiles(id) on delete cascade, role_id text not null references public.admin_role_definitions(id),
 assigned_by uuid references public.profiles(id), assigned_at timestamptz not null default now(), primary key(user_id,role_id)
);
alter table public.admin_role_definitions enable row level security;
alter table public.admin_role_assignments enable row level security;
create policy admin_roles_read on public.admin_role_definitions for select to authenticated using(public.is_admin());
create policy admin_assignments_read on public.admin_role_assignments for select to authenticated using(public.is_admin());

insert into public.admin_role_assignments(user_id,role_id,assigned_by)
select distinct ur.profile_id,'super_admin',ur.profile_id from public.user_roles ur where ur.role in ('admin','owner') on conflict do nothing;

create or replace function public.is_super_admin(check_user uuid default auth.uid()) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.admin_role_assignments where user_id=check_user and role_id='super_admin')
 or exists(select 1 from public.user_roles where profile_id=check_user and role='owner');
$$;
create or replace function public.has_admin_permission(p_permission text,check_user uuid default auth.uid()) returns boolean language sql stable security definer set search_path=public as $$
 select public.is_super_admin(check_user) or exists(select 1 from public.admin_role_assignments a join public.admin_role_definitions r on r.id=a.role_id where a.user_id=check_user and r.is_active and (r.permissions ? p_permission or r.permissions ? '*'));
$$;
grant execute on function public.is_super_admin(uuid) to authenticated;
grant execute on function public.has_admin_permission(text,uuid) to authenticated;

create or replace function public.assign_admin_role(p_user_id uuid,p_role_id text,p_assign boolean default true) returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_super_admin() then raise exception 'Only a Super Admin can assign administrative roles'; end if;
 if not exists(select 1 from public.admin_role_definitions where id=p_role_id and is_active) then raise exception 'Unknown admin role'; end if;
 if p_assign then
  insert into public.admin_role_assignments(user_id,role_id,assigned_by) values(p_user_id,p_role_id,auth.uid()) on conflict(user_id,role_id) do update set assigned_by=auth.uid(),assigned_at=now();
  insert into public.user_roles(profile_id,role) values(p_user_id,'admin') on conflict do nothing;
 else
  if p_user_id=auth.uid() and p_role_id='super_admin' and (select count(*) from public.admin_role_assignments where role_id='super_admin')<=1 then raise exception 'The final Super Admin cannot remove their own role'; end if;
  delete from public.admin_role_assignments where user_id=p_user_id and role_id=p_role_id;
 end if;
 insert into public.audit_logs(actor_id,action,target_table,target_id,metadata) values(auth.uid(),case when p_assign then 'admin_role_assigned' else 'admin_role_removed' end,'profiles',p_user_id,jsonb_build_object('role_id',p_role_id));
end $$;
grant execute on function public.assign_admin_role(uuid,text,boolean) to authenticated;

create or replace function public.get_admin_role_directory() returns table(user_id uuid,full_name text,account_email text,roles jsonb)
language sql stable security definer set search_path=public as $$
 select p.id,p.full_name,p.account_email,coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',r.name) order by r.rank desc) filter(where r.id is not null),'[]'::jsonb)
 from public.profiles p join public.user_roles ur on ur.profile_id=p.id and ur.role in ('admin','owner') left join public.admin_role_assignments a on a.user_id=p.id left join public.admin_role_definitions r on r.id=a.role_id
 where public.is_admin() group by p.id,p.full_name,p.account_email order by p.full_name;
$$;
grant execute on function public.get_admin_role_directory() to authenticated;

create table if not exists public.agent_wallet_transactions(
 id uuid primary key default gen_random_uuid(),agent_id uuid not null references public.agents(id) on delete cascade,
 transaction_type text not null check(transaction_type in ('credit','debit','refund','adjustment')),
 balance_kind text not null check(balance_kind in ('available','promotional')),amount_tzs numeric(14,2) not null check(amount_tzs>0),
 description text not null,reference_type text,reference_id uuid,created_by uuid references public.profiles(id),created_at timestamptz not null default now()
);
alter table public.agent_wallet_transactions enable row level security;
create policy wallet_transactions_read on public.agent_wallet_transactions for select to authenticated using(public.is_admin() or agent_id=public.current_agent_id());

create or replace function public.admin_adjust_agent_wallet(p_agent_id uuid,p_balance_kind text,p_amount_tzs numeric,p_description text) returns void language plpgsql security definer set search_path=public as $$
declare v_type text;
begin
 if not public.has_admin_permission('wallets.manage') then raise exception 'Finance permission required'; end if;
 if p_balance_kind not in ('available','promotional') or p_amount_tzs=0 then raise exception 'Invalid wallet adjustment'; end if;
 v_type:=case when p_amount_tzs>0 then 'credit' else 'debit' end;
 insert into public.agent_wallets(agent_id) values(p_agent_id) on conflict do nothing;
 if p_balance_kind='available' then update public.agent_wallets set available_balance_tzs=greatest(0,available_balance_tzs+p_amount_tzs),updated_at=now() where agent_id=p_agent_id;
 else update public.agent_wallets set promotional_credits_tzs=greatest(0,promotional_credits_tzs+p_amount_tzs),updated_at=now() where agent_id=p_agent_id; end if;
 insert into public.agent_wallet_transactions(agent_id,transaction_type,balance_kind,amount_tzs,description,created_by) values(p_agent_id,v_type,p_balance_kind,abs(p_amount_tzs),p_description,auth.uid());
end $$;
grant execute on function public.admin_adjust_agent_wallet(uuid,text,numeric,text) to authenticated;
