-- Home category rails must receive newest listings before pagination.
-- Preserve the existing RPC signature, visibility rules and location behavior.
create or replace function public.get_public_home_feed(
  p_limit integer default 20,
  p_page integer default 0,
  p_selected_region_id uuid default null,
  p_selected_district_id uuid default null,
  p_selected_ward_id uuid default null,
  p_selected_area_id uuid default null,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_session_seed text default null
)
returns table (
  listing_id uuid, title text, public_location_label text, price_amount numeric,
  price_period text, category_id uuid, category_name text, category_slug text,
  category_icon_key text, home_feed_weight integer, cover_storage_path text,
  region_id uuid, district_id uuid
)
language sql stable security definer set search_path = public
as $$
  with detected as (
    select * from public.resolve_location_hierarchy(p_latitude, p_longitude)
    where p_latitude is not null and p_longitude is not null
  ), wanted as (
    select
      coalesce(p_selected_region_id, d.region_id) region_id,
      coalesce(p_selected_district_id, d.district_id) district_id,
      coalesce(p_selected_ward_id, d.ward_id) ward_id,
      coalesce(p_selected_area_id, d.area_id) area_id
    from (select 1) x left join detected d on true
  ), eligible as (
    select
      l.id listing_id, l.title, l.public_location_label, l.price_amount,
      l.price_period::text price_period, c.id category_id, c.name category_name,
      c.slug category_slug, c.icon_key category_icon_key, c.home_feed_weight,
      public.normalize_listing_media_path(lm.storage_path) cover_storage_path,
      public.location_ancestor_id(l.location_id, 'region'::public.location_type) region_id,
      public.location_ancestor_id(l.location_id, 'district'::public.location_type) district_id,
      coalesce(l.published_at, l.created_at) freshness_at,
      case
        when w.area_id is not null and public.location_ancestor_id(l.location_id, 'area'::public.location_type) = w.area_id then 1
        when w.ward_id is not null and public.location_ancestor_id(l.location_id, 'ward'::public.location_type) = w.ward_id then 2
        when w.district_id is not null and public.location_ancestor_id(l.location_id, 'district'::public.location_type) = w.district_id then 3
        when w.region_id is not null then 4 else 5
      end priority_group,
      ((('x' || substr(md5(coalesce(p_session_seed, to_char(current_date, 'YYYYMMDD')) || ':' || l.id::text), 1, 8))::bit(32)::bigint)::numeric + 1) / 4294967296::numeric random_unit,
      (w.region_id is not null) has_location_signal
    from public.listings l
    join public.agents a on a.id = l.agent_id and a.account_status = 'active'::public.agent_account_status
    join public.asset_categories c on c.id = l.category_id and c.is_active = true
    left join public.listing_media lm on lm.listing_id = l.id and lm.is_cover = true
    cross join wanted w
    where l.status = 'active'::public.listing_status
      and l.availability_status = 'available'::public.availability_status
      and l.removed_from_market_at is null
      and (w.region_id is null or public.location_ancestor_id(l.location_id, 'region'::public.location_type) = w.region_id)
  )
  select listing_id, title, public_location_label, price_amount, price_period,
    category_id, category_name, category_slug, category_icon_key, home_feed_weight,
    cover_storage_path, region_id, district_id
  from eligible
  order by freshness_at desc nulls last, listing_id
  offset greatest(coalesce(p_page, 0), 0) * greatest(least(coalesce(p_limit, 20), 50), 1)
  limit greatest(least(coalesce(p_limit, 20), 50), 1);
$$;


notify pgrst, 'reload schema';
