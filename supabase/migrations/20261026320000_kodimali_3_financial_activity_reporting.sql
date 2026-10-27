-- KODIMALI 3.0: permission-scoped, read-only financial activity feed for
-- filtering and controlled report export. Posted journals remain immutable.

create or replace function public.get_admin_financial_activity(
  p_from timestamptz default null,
  p_until timestamptz default null,
  p_product text default null,
  p_status text default null,
  p_booking_id uuid default null,
  p_provider_profile_id uuid default null,
  p_category text default null,
  p_payment_provider text default null,
  p_limit integer default 200
)
returns table(
  payment_intent_id uuid,
  created_at timestamptz,
  verified_at timestamptz,
  product text,
  status text,
  amount_minor bigint,
  currency text,
  resource_type text,
  resource_id uuid,
  booking_id uuid,
  provider_profile_id uuid,
  category text,
  payment_provider text,
  provider_order_id text,
  provider_transaction_id text
)
language plpgsql
security definer
set search_path = public
as $$
declare v_limit integer := least(greatest(coalesce(p_limit,200),1),500);
begin
  if not (public.has_admin_permission('payments.view') or public.has_admin_permission('payments.manage')) then
    raise exception 'Financial reporting permission required';
  end if;
  if p_from is not null and p_until is not null and p_from >= p_until then
    raise exception 'Report end must be after its start';
  end if;

  insert into public.audit_logs(actor_id,action,target_table,metadata)
  values(auth.uid(),'financial_activity_viewed','payment_intents',jsonb_strip_nulls(jsonb_build_object(
    'from',p_from,'until',p_until,'product',p_product,'status',p_status,
    'booking_id',p_booking_id,'provider_profile_id',p_provider_profile_id,
    'category',p_category,'payment_provider',p_payment_provider,'limit',v_limit
  )));

  return query
  select
    i.id,
    i.created_at,
    i.verified_at,
    i.product,
    i.status,
    i.amount_minor,
    i.currency,
    i.resource_type,
    i.resource_id,
    case when i.resource_type='booking_request' then i.resource_id else null end,
    coalesce(pp.provider_profile_id,controlling_owner.profile_id,a.profile_id),
    coalesce(c.slug,l.category::text),
    i.provider,
    i.provider_order_id,
    i.provider_transaction_id
  from public.payment_intents i
  left join public.booking_requests b
    on i.resource_type='booking_request' and b.id=i.resource_id
  left join public.listings l on l.id=b.listing_id
  left join public.asset_categories c on c.id=l.category_id
  left join public.agents a on a.id=b.agent_id
  left join lateral (
    select pp.provider_profile_id
    from public.provider_payables pp
    where pp.booking_request_id=b.id
    order by pp.created_at desc
    limit 1
  ) pp on true
  left join lateral (
    select op.profile_id
    from public.owner_asset_claims oc
    join public.owner_profiles op on op.id=oc.owner_id
    where oc.asset_id=l.asset_id and oc.status='verified'
    order by oc.verified_at desc nulls last, oc.created_at desc
    limit 1
  ) controlling_owner on true
  where (p_from is null or i.created_at>=p_from)
    and (p_until is null or i.created_at<p_until)
    and (nullif(trim(p_product),'') is null or i.product=p_product)
    and (nullif(trim(p_status),'') is null or i.status=p_status)
    and (p_booking_id is null or (i.resource_type='booking_request' and i.resource_id=p_booking_id))
    and (p_provider_profile_id is null or coalesce(pp.provider_profile_id,controlling_owner.profile_id,a.profile_id)=p_provider_profile_id)
    and (nullif(trim(p_category),'') is null or coalesce(c.slug,l.category::text)=p_category)
    and (nullif(trim(p_payment_provider),'') is null or i.provider=p_payment_provider)
  order by i.created_at desc, i.id desc
  limit v_limit;
end;
$$;

revoke all on function public.get_admin_financial_activity(timestamptz,timestamptz,text,text,uuid,uuid,text,text,integer)
from public, anon, authenticated;
grant execute on function public.get_admin_financial_activity(timestamptz,timestamptz,text,text,uuid,uuid,text,text,integer)
to authenticated, service_role;

comment on function public.get_admin_financial_activity(timestamptz,timestamptz,text,text,uuid,uuid,text,text,integer) is
'Returns an audited, permission-scoped payment-intent report for Financial Control Center filtering and export.';

