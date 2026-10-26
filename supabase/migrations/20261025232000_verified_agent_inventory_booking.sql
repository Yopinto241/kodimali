-- A verified, active agent is an accountable controller for inventory attached
-- to their own listings. Keep owner/manager claims as the alternative path.

update public.rental_assets a
set verification_status = 'verified',
    owner_advertising_authorized = true,
    authorization_evidence = coalesce(a.authorization_evidence, '{}'::jsonb)
      || jsonb_build_object('verification_source', 'verified_listing_agent'),
    verified_at = coalesce(a.verified_at, timezone('utc', now())),
    updated_at = timezone('utc', now())
from public.listings l
join public.agents ag on ag.id = l.agent_id
where l.asset_id = a.id
  and ag.verification_status = 'approved'
  and ag.account_status = 'active'
  and a.verification_status <> 'verified';

create or replace function public.sync_verified_agent_assets()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.verification_status = 'approved' and new.account_status = 'active' then
    update public.rental_assets a
    set verification_status = 'verified',
        owner_advertising_authorized = true,
        authorization_evidence = coalesce(a.authorization_evidence, '{}'::jsonb)
          || jsonb_build_object('verification_source', 'verified_listing_agent'),
        verified_at = coalesce(a.verified_at, timezone('utc', now())),
        updated_at = timezone('utc', now())
    from public.listings l
    where l.asset_id = a.id
      and l.agent_id = new.id
      and a.verification_status <> 'verified';
  end if;
  return new;
end;
$$;

drop trigger if exists sync_verified_agent_assets on public.agents;
create trigger sync_verified_agent_assets
after insert or update of verification_status, account_status on public.agents
for each row execute function public.sync_verified_agent_assets();

create or replace function public.sync_verified_listing_asset()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.asset_id is not null and exists (
    select 1 from public.agents ag
    where ag.id = new.agent_id
      and ag.verification_status = 'approved'
      and ag.account_status = 'active'
  ) then
    update public.rental_assets
    set verification_status = 'verified',
        owner_advertising_authorized = true,
        authorization_evidence = coalesce(authorization_evidence, '{}'::jsonb)
          || jsonb_build_object('verification_source', 'verified_listing_agent'),
        verified_at = coalesce(verified_at, timezone('utc', now())),
        updated_at = timezone('utc', now())
    where id = new.asset_id
      and verification_status <> 'verified';
  end if;
  return new;
end;
$$;

drop trigger if exists sync_verified_listing_asset on public.listings;
create trigger sync_verified_listing_asset
after insert or update of agent_id, asset_id on public.listings
for each row execute function public.sync_verified_listing_asset();

create or replace function public.enforce_verified_reservable_booking()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_category text;
  v_asset_id uuid;
begin
  select c.slug, l.asset_id
    into v_category, v_asset_id
  from public.listings l
  join public.asset_categories c on c.id = l.category_id
  where l.id = new.listing_id;

  if v_category in ('house','apartment','car','motorcycle','office','meeting-hall','ceremony-hall')
     and (new.requested_start_at is not null
          or new.requested_end_at is not null
          or new.booking_kind = 'reservation') then
    if new.requested_start_at is null or new.requested_end_at is null
       or new.requested_end_at <= new.requested_start_at then
      raise exception 'A valid booking start and end period is required';
    end if;
    if v_asset_id is null then
      raise exception 'This listing is not connected to verified inventory';
    end if;
    if not exists (
      select 1 from public.rental_assets a
      where a.id = v_asset_id and a.verification_status = 'verified'
    ) then
      raise exception 'The listed item must be verified before it can accept bookings';
    end if;
    if not (
      exists (
        select 1
        from public.owner_asset_claims c
        join public.owner_profiles o on o.id = c.owner_id
        where c.asset_id = v_asset_id
          and c.status = 'verified'
          and c.authority_type in ('owner','authorized_manager')
          and o.verification_status = 'verified'
      )
      or exists (
        select 1
        from public.listings l
        join public.agents ag on ag.id = l.agent_id
        where l.id = new.listing_id
          and l.asset_id = v_asset_id
          and ag.verification_status = 'approved'
          and ag.account_status = 'active'
      )
    ) then
      raise exception 'A verified owner, manager or listing agent is required before booking';
    end if;

    new.booking_kind := 'reservation';
    if new.owner_approval_status in ('not_required','expired') then
      new.owner_approval_status := 'pending';
      new.owner_response_deadline := now() + interval '24 hours';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.listing_booking_readiness(p_listing_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'ready',
      l.asset_id is not null
      and a.verification_status = 'verified'
      and (
        exists (
          select 1 from public.owner_asset_claims c
          join public.owner_profiles o on o.id = c.owner_id
          where c.asset_id = l.asset_id
            and c.status = 'verified'
            and c.authority_type in ('owner','authorized_manager')
            and o.verification_status = 'verified'
        )
        or (ag.verification_status = 'approved' and ag.account_status = 'active')
      ),
    'asset_verified', coalesce(a.verification_status = 'verified', false),
    'verified_controller',
      exists (
        select 1 from public.owner_asset_claims c
        join public.owner_profiles o on o.id = c.owner_id
        where c.asset_id = l.asset_id
          and c.status = 'verified'
          and c.authority_type in ('owner','authorized_manager')
          and o.verification_status = 'verified'
      )
      or coalesce(ag.verification_status = 'approved' and ag.account_status = 'active', false)
  )
  from public.listings l
  left join public.rental_assets a on a.id = l.asset_id
  left join public.agents ag on ag.id = l.agent_id
  where l.id = p_listing_id
    and public.is_listing_public(l.id);
$$;

revoke all on function public.listing_booking_readiness(uuid) from public;
grant execute on function public.listing_booking_readiness(uuid)
  to anon, authenticated, service_role;

