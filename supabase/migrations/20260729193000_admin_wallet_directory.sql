create or replace function public.get_admin_agent_wallets()
returns table(agent_id uuid,business_name text,display_name text,available_balance_tzs numeric,promotional_credits_tzs numeric,lifetime_revenue_tzs numeric)
language sql stable security definer set search_path=public as $$
 select a.id,a.business_name,a.display_name,w.available_balance_tzs,w.promotional_credits_tzs,w.lifetime_revenue_tzs
 from public.agents a join public.agent_wallets w on w.agent_id=a.id where public.has_admin_permission('wallets.manage') order by coalesce(a.business_name,a.display_name);
$$;
grant execute on function public.get_admin_agent_wallets() to authenticated;
