-- Backfill legacy public listings that predate rental_assets, and make the
-- linkage automatic for future listings controlled by verified agents.

insert into public.rental_assets (
  category,
  location_id,
  fingerprint,
  display_name,
  verification_status,
  owner_advertising_authorized,
  authorization_evidence,
  verified_at
)
select
  case c.slug
    when 'house' then 'house'::public.listing_category
    when 'car' then 'car'::public.listing_category
    when 'motorcycle' then 'motorcycle'::public.listing_category
    when 'office' then 'office'::public.listing_category
    when 'meeting-hall' then 'meeting_hall'::public.listing_category
    when 'ceremony-hall' then 'ceremony_hall'::public.listing_category
    when 'equipment' then 'equipment'::public.listing_category
    else 'other_asset'::public.listing_category
  end,
  l.location_id,
  'listing-' || l.id::text,
  l.title,
  'verified',
  true,
  jsonb_build_object(
    'verification_source', 'verified_listing_agent',
    'listing_id', l.id,
    'agent_id', l.agent_id
  ),
  timezone('utc', now())
from public.listings l
join public.agents ag on ag.id = l.agent_id
join public.asset_categories c on c.id = l.category_id
where l.asset_id is null
  and ag.verification_status = 'approved'
  and ag.account_status = 'active'
on conflict (category, fingerprint) do nothing;

-- This is a one-time system reconciliation, not an agent-authored listing edit.
-- Bypass user-facing listing mutation triggers while only attaching asset IDs.
set local session_replication_role = replica;

update public.listings l
set asset_id = a.id,
    updated_at = timezone('utc', now())
from public.rental_assets a,
     public.asset_categories c
where l.asset_id is null
  and c.id = l.category_id
  and a.category = case c.slug
    when 'house' then 'house'::public.listing_category
    when 'car' then 'car'::public.listing_category
    when 'motorcycle' then 'motorcycle'::public.listing_category
    when 'office' then 'office'::public.listing_category
    when 'meeting-hall' then 'meeting_hall'::public.listing_category
    when 'ceremony-hall' then 'ceremony_hall'::public.listing_category
    when 'equipment' then 'equipment'::public.listing_category
    else 'other_asset'::public.listing_category
  end
  and a.fingerprint = 'listing-' || l.id::text;

set local session_replication_role = origin;

drop trigger if exists sync_verified_listing_asset on public.listings;

create or replace function public.sync_verified_listing_asset()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_asset_id uuid;
  v_category public.listing_category;
begin
  if exists (
    select 1 from public.agents ag
    where ag.id = new.agent_id
      and ag.verification_status = 'approved'
      and ag.account_status = 'active'
  ) then
    if new.asset_id is null then
      select case c.slug
        when 'house' then 'house'::public.listing_category
        when 'car' then 'car'::public.listing_category
        when 'motorcycle' then 'motorcycle'::public.listing_category
        when 'office' then 'office'::public.listing_category
        when 'meeting-hall' then 'meeting_hall'::public.listing_category
        when 'ceremony-hall' then 'ceremony_hall'::public.listing_category
        when 'equipment' then 'equipment'::public.listing_category
        else 'other_asset'::public.listing_category
      end into v_category
      from public.asset_categories c
      where c.id = new.category_id;

      insert into public.rental_assets (
        category, location_id, fingerprint, display_name,
        verification_status, owner_advertising_authorized,
        authorization_evidence, verified_at
      ) values (
        v_category,
        new.location_id, 'listing-' || new.id::text, new.title,
        'verified', true,
        jsonb_build_object(
          'verification_source', 'verified_listing_agent',
          'listing_id', new.id,
          'agent_id', new.agent_id
        ),
        timezone('utc', now())
      )
      on conflict (category, fingerprint) do update
        set display_name = excluded.display_name,
            location_id = excluded.location_id,
            verification_status = 'verified',
            owner_advertising_authorized = true,
            authorization_evidence = public.rental_assets.authorization_evidence
              || excluded.authorization_evidence,
            verified_at = coalesce(
              public.rental_assets.verified_at,
              timezone('utc', now())
            ),
            updated_at = timezone('utc', now())
      returning id into v_asset_id;
      new.asset_id := v_asset_id;
    else
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
  end if;
  return new;
end;
$$;

create trigger sync_verified_listing_asset
before insert or update of agent_id, asset_id on public.listings
for each row execute function public.sync_verified_listing_asset();

