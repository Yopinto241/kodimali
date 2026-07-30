alter table public.agent_listing_payments drop constraint if exists agent_listing_payments_requested_amount_check;
alter table public.agent_listing_payments add constraint agent_listing_payments_requested_amount_check check(requested_amount>=0);

create or replace function public.assert_agent_plan_listing_capacity(p_agent_id uuid,p_listing_id uuid)
returns void language plpgsql stable security definer set search_path=public as $$
declare v_limit integer; v_active integer;
begin
 select p.listing_limit into v_limit from public.agent_subscriptions s join public.agent_subscription_plans p on p.id=s.plan_id
 where s.agent_id=p_agent_id and s.status='active' and (s.expires_at is null or s.expires_at>now()) limit 1;
 if v_limit is null then return; end if;
 select count(*) into v_active from public.listings where agent_id=p_agent_id and status='active' and id<>p_listing_id;
 if v_active>=v_limit then raise exception 'Your current plan allows % active listings. Upgrade your plan or deactivate another listing.',v_limit; end if;
end $$;
grant execute on function public.assert_agent_plan_listing_capacity(uuid,uuid) to authenticated,service_role;
