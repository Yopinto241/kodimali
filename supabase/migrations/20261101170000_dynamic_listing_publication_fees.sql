-- One authoritative effective fee for global free mode and zero-fee plans.
create or replace function public.agent_listing_publication_fee(p_agent_id uuid)
returns integer language sql stable security definer set search_path=public as $$
 select case when not public.agent_listing_payments_enabled() then 0 else
 coalesce((select p.publication_fee_tzs from public.agent_subscriptions s
 join public.agent_subscription_plans p on p.id=s.plan_id
 where s.agent_id=p_agent_id and s.status='active'
 and (s.expires_at is null or s.expires_at>now()) limit 1),1000) end
$$;
revoke all on function public.agent_listing_publication_fee(uuid) from public,anon,authenticated;
grant execute on function public.agent_listing_publication_fee(uuid) to service_role;

create or replace function public.get_agent_listing_publication_mode()
returns table(payment_required boolean,amount_tzs integer,agent_verified boolean,admin_approval_required boolean)
language sql stable security definer set search_path=public as $$
 select fee.amount>0,fee.amount,
 coalesce(ag.verification_status='approved' and ag.account_status='active',false),
 not coalesce(ag.verification_status='approved' and ag.account_status='active',false)
 from (select 1) seed left join public.agents ag on ag.profile_id=auth.uid()
 cross join lateral (select public.agent_listing_publication_fee(ag.id) amount) fee
 limit 1
$$;
revoke all on function public.get_agent_listing_publication_mode() from public,anon;
grant execute on function public.get_agent_listing_publication_mode() to authenticated;

create or replace function public.enforce_agent_listing_payment_before_publish()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status='active' and old.status is distinct from 'active'
 and public.agent_listing_publication_fee(new.agent_id)>0
 and not exists(select 1 from public.agent_listing_payments p where p.listing_id=new.id
 and p.agent_id=new.agent_id and p.payment_status='paid') then
 raise exception 'Agent listing payment is required before publication' using errcode='P0001';
 end if;
 return new;
end $$;

create or replace function public.release_agent_listing_if_eligible(p_listing_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_changed_count integer := 0;
begin
  update public.listings l
  set status = 'active'::public.listing_status,
      publication_requested = false,
      removed_from_market_at = null,
      removed_reason = null,
      published_at = coalesce(l.published_at, timezone('utc', now()))
  from public.agents ag
  where l.id = p_listing_id
    and ag.id = l.agent_id
    and l.status = 'inactive'::public.listing_status
    and l.removed_from_market_at is null
    and l.removed_reason is null
    and public.listing_has_publishable_media(l.id)
    and (
      (ag.verification_status = 'approved' and ag.account_status = 'active')
      or l.publication_review_status = 'admin_approved'
    )
    and (
      public.agent_listing_publication_fee(ag.id) = 0
      or exists (
        select 1 from public.agent_listing_payments p
        where p.listing_id = l.id
          and p.agent_id = l.agent_id
          and p.payment_status = 'paid'
      )
    );
  get diagnostics v_changed_count = row_count;
  return v_changed_count > 0;
end;
$$;


-- Preserve the current admin authorization/audit implementation; change only
-- its payment decision so a zero-fee plan also works after manual approval.
do $migration$
declare definition text;
begin
 definition:=pg_get_functiondef('public.admin_set_listing_marketplace_status(uuid,public.listing_status,public.availability_status,text,text)'::regprocedure);
 if position('v_payment_required := public.agent_listing_payments_enabled();' in definition)=0 then
  raise exception 'Unexpected admin publication implementation; migration not applied';
 end if;
 execute replace(definition,'v_payment_required := public.agent_listing_payments_enabled();',
 'v_payment_required := public.agent_listing_publication_fee(v_listing.agent_id) > 0;');
end $migration$;
notify pgrst, 'reload schema';
