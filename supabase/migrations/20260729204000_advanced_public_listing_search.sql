create index if not exists listings_public_price_search_idx
  on public.listings (price_period, price_amount, coalesce(published_at, created_at) desc, id)
  where status = 'active'::public.listing_status
    and availability_status = 'available'::public.availability_status
    and removed_from_market_at is null;

create or replace function public.search_public_listings_v2(
  p_category_slug text,
  p_search_text text,
  p_region_id uuid,
  p_district_id uuid,
  p_ward_id uuid,
  p_area_id uuid,
  p_min_price numeric,
  p_max_price numeric,
  p_price_period text,
  p_sort text,
  p_limit integer,
  p_page integer,
  p_latitude double precision,
  p_longitude double precision,
  p_session_seed text
)
returns table (
  listing_id uuid,
  title text,
  public_location_label text,
  price_amount numeric,
  price_period text,
  availability_status text,
  category_id uuid,
  category_name text,
  category_slug text,
  category_icon_key text,
  home_feed_weight integer,
  cover_storage_path text,
  region_id uuid,
  district_id uuid,
  published_at timestamptz,
  total_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with eligible as (
    select
      l.id as listing_id,
      l.title,
      l.public_location_label,
      l.price_amount,
      l.price_period::text as price_period,
      l.availability_status::text as availability_status,
      c.id as category_id,
      c.name as category_name,
      c.slug as category_slug,
      c.icon_key as category_icon_key,
      c.home_feed_weight,
      public.normalize_listing_media_path(lm.storage_path) as cover_storage_path,
      public.location_ancestor_id(l.location_id, 'region'::public.location_type) as region_id,
      public.location_ancestor_id(l.location_id, 'district'::public.location_type) as district_id,
      coalesce(l.published_at, l.created_at) as published_at,
      case
        when p_latitude is not null and p_longitude is not null
          and loc.latitude is not null and loc.longitude is not null
        then power(loc.latitude - p_latitude, 2) + power(loc.longitude - p_longitude, 2)
        else null
      end as gps_distance_score,
      case
        when p_area_id is not null and public.location_ancestor_id(l.location_id, 'area'::public.location_type) = p_area_id then 1
        when p_ward_id is not null and public.location_ancestor_id(l.location_id, 'ward'::public.location_type) = p_ward_id then 2
        when p_district_id is not null and public.location_ancestor_id(l.location_id, 'district'::public.location_type) = p_district_id then 3
        when p_region_id is not null and public.location_ancestor_id(l.location_id, 'region'::public.location_type) = p_region_id then 4
        when p_latitude is not null and p_longitude is not null then 5
        else 6
      end as priority_group,
      ((('x' || substr(md5(coalesce(p_session_seed, to_char(current_date, 'YYYYMMDD')) || ':' || l.id::text), 1, 8))::bit(32)::bigint)::numeric + 1) / 4294967296::numeric as random_unit,
      (p_region_id is not null or p_district_id is not null or p_ward_id is not null or p_area_id is not null or (p_latitude is not null and p_longitude is not null)) as has_location_signal
    from public.listings l
    join public.agents a on a.id = l.agent_id and a.account_status = 'active'::public.agent_account_status
    join public.asset_categories c on c.id = l.category_id and c.is_active = true
    left join public.locations loc on loc.id = l.location_id
    left join public.listing_media lm on lm.listing_id = l.id and lm.is_cover = true
    where l.status = 'active'::public.listing_status
      and l.availability_status = 'available'::public.availability_status
      and l.removed_from_market_at is null
      and (p_category_slug is null or btrim(p_category_slug) = '' or c.slug = p_category_slug)
      and (p_min_price is null or l.price_amount >= greatest(p_min_price, 0))
      and (p_max_price is null or l.price_amount <= p_max_price)
      and (p_price_period is null or btrim(p_price_period) = '' or l.price_period::text = p_price_period)
      and (
        p_search_text is null or btrim(p_search_text) = ''
        or l.title ilike '%' || btrim(p_search_text) || '%'
        or l.description ilike '%' || btrim(p_search_text) || '%'
        or l.public_location_label ilike '%' || btrim(p_search_text) || '%'
        or c.name ilike '%' || btrim(p_search_text) || '%'
        or l.listing_attributes::text ilike '%' || btrim(p_search_text) || '%'
      )
  ), counted as (
    select eligible.*, count(*) over () as total_count
    from eligible
  )
  select
    listing_id, title, public_location_label, price_amount, price_period,
    availability_status, category_id, category_name, category_slug,
    category_icon_key, home_feed_weight, cover_storage_path, region_id,
    district_id, published_at, total_count
  from counted
  order by
    case when coalesce(p_sort, 'recommended') = 'price_low' then price_amount end asc nulls last,
    case when coalesce(p_sort, 'recommended') = 'price_high' then price_amount end desc nulls last,
    case when coalesce(p_sort, 'recommended') = 'newest' then published_at end desc nulls last,
    case when coalesce(p_sort, 'recommended') = 'recommended' and has_location_signal then priority_group end asc nulls last,
    case when coalesce(p_sort, 'recommended') = 'recommended' and has_location_signal then gps_distance_score end asc nulls last,
    case when coalesce(p_sort, 'recommended') = 'recommended' and not has_location_signal then random_unit end asc nulls last,
    case when p_search_text is null or btrim(p_search_text) = '' then 0 when title ilike btrim(p_search_text) || '%' then 0 else 1 end,
    published_at desc,
    listing_id
  offset greatest(coalesce(p_page, 0), 0) * greatest(least(coalesce(p_limit, 20), 50), 1)
  limit greatest(least(coalesce(p_limit, 20), 50), 1);
$$;

revoke all on function public.search_public_listings_v2(text, text, uuid, uuid, uuid, uuid, numeric, numeric, text, text, integer, integer, double precision, double precision, text) from public;
grant execute on function public.search_public_listings_v2(text, text, uuid, uuid, uuid, uuid, numeric, numeric, text, text, integer, integer, double precision, double precision, text) to anon, authenticated, service_role;
