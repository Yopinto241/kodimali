create index if not exists listings_public_location_browse_idx
  on public.listings (
    location_id,
    category_id,
    coalesce(published_at, created_at) desc,
    id
  )
  where status = 'active'::public.listing_status
    and availability_status = 'available'::public.availability_status
    and removed_from_market_at is null;

create index if not exists listings_public_category_browse_idx
  on public.listings (
    category_id,
    location_id,
    coalesce(published_at, created_at) desc,
    id
  )
  where status = 'active'::public.listing_status
    and availability_status = 'available'::public.availability_status
    and removed_from_market_at is null;

drop function if exists public.get_public_home_feed(
  integer,
  integer,
  uuid,
  uuid,
  uuid,
  uuid,
  double precision,
  double precision,
  text
);

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
  listing_id uuid,
  title text,
  public_location_label text,
  price_amount numeric,
  price_period text,
  category_id uuid,
  category_name text,
  category_slug text,
  category_icon_key text,
  home_feed_weight integer,
  cover_storage_path text,
  region_id uuid,
  district_id uuid
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
      c.id as category_id,
      c.name as category_name,
      c.slug as category_slug,
      c.icon_key as category_icon_key,
      c.home_feed_weight,
      public.normalize_listing_media_path(lm.storage_path) as cover_storage_path,
      public.location_ancestor_id(l.location_id, 'region'::public.location_type) as region_id,
      public.location_ancestor_id(l.location_id, 'district'::public.location_type) as district_id,
      public.location_ancestor_id(l.location_id, 'ward'::public.location_type) as ward_id,
      public.location_ancestor_id(l.location_id, 'area'::public.location_type) as area_id,
      coalesce(l.published_at, l.created_at) as freshness_at,
      case
        when p_latitude is not null
         and p_longitude is not null
         and loc.latitude is not null
         and loc.longitude is not null
        then power(loc.latitude - p_latitude, 2) + power(loc.longitude - p_longitude, 2)
        else null
      end as gps_distance_score,
      case
        when p_selected_area_id is not null
         and public.location_ancestor_id(l.location_id, 'area'::public.location_type) = p_selected_area_id then 1
        when p_selected_ward_id is not null
         and public.location_ancestor_id(l.location_id, 'ward'::public.location_type) = p_selected_ward_id then 2
        when p_selected_district_id is not null
         and public.location_ancestor_id(l.location_id, 'district'::public.location_type) = p_selected_district_id then 3
        when p_selected_region_id is not null
         and public.location_ancestor_id(l.location_id, 'region'::public.location_type) = p_selected_region_id then 4
        when p_latitude is not null and p_longitude is not null then 5
        else 6
      end as priority_group,
      (
        ((('x' || substr(
          md5(coalesce(p_session_seed, to_char(current_date, 'YYYYMMDD')) || ':' || l.id::text),
          1,
          8
        ))::bit(32)::bigint)::numeric + 1)
      ) / 4294967296::numeric as random_unit,
      (
        p_selected_region_id is not null
        or p_selected_district_id is not null
        or p_selected_ward_id is not null
        or p_selected_area_id is not null
        or (p_latitude is not null and p_longitude is not null)
      ) as has_location_signal
    from public.listings l
    join public.agents a
      on a.id = l.agent_id
     and a.account_status = 'active'::public.agent_account_status
    join public.asset_categories c
      on c.id = l.category_id
     and c.is_active = true
    left join public.locations loc on loc.id = l.location_id
    left join public.listing_media lm
      on lm.listing_id = l.id
     and lm.is_cover = true
    where l.status = 'active'::public.listing_status
      and l.availability_status = 'available'::public.availability_status
      and l.removed_from_market_at is null
  )
  select
    listing_id,
    title,
    public_location_label,
    price_amount,
    price_period,
    category_id,
    category_name,
    category_slug,
    category_icon_key,
    home_feed_weight,
    cover_storage_path,
    region_id,
    district_id
  from eligible
  order by
    case when has_location_signal then priority_group else 0 end asc,
    case when has_location_signal then gps_distance_score end nulls last,
    case when not has_location_signal then random_unit end asc nulls last,
    freshness_at desc,
    listing_id
  offset greatest(coalesce(p_page, 0), 0) * greatest(least(coalesce(p_limit, 20), 50), 1)
  limit greatest(least(coalesce(p_limit, 20), 50), 1);
$$;

drop function if exists public.get_public_listings(
  text,
  text,
  uuid,
  uuid,
  uuid,
  uuid,
  integer,
  integer,
  double precision,
  double precision,
  text
);

create or replace function public.get_public_listings(
  p_category_slug text default null,
  p_search_text text default null,
  p_region_id uuid default null,
  p_district_id uuid default null,
  p_ward_id uuid default null,
  p_area_id uuid default null,
  p_limit integer default 20,
  p_page integer default 0,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_session_seed text default null
)
returns table (
  listing_id uuid,
  title text,
  public_location_label text,
  price_amount numeric,
  price_period text,
  category_id uuid,
  category_name text,
  category_slug text,
  category_icon_key text,
  home_feed_weight integer,
  cover_storage_path text,
  region_id uuid,
  district_id uuid
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
      c.id as category_id,
      c.name as category_name,
      c.slug as category_slug,
      c.icon_key as category_icon_key,
      c.home_feed_weight,
      public.normalize_listing_media_path(lm.storage_path) as cover_storage_path,
      public.location_ancestor_id(l.location_id, 'region'::public.location_type) as region_id,
      public.location_ancestor_id(l.location_id, 'district'::public.location_type) as district_id,
      public.location_ancestor_id(l.location_id, 'ward'::public.location_type) as ward_id,
      public.location_ancestor_id(l.location_id, 'area'::public.location_type) as area_id,
      coalesce(l.published_at, l.created_at) as freshness_at,
      case
        when p_latitude is not null
         and p_longitude is not null
         and loc.latitude is not null
         and loc.longitude is not null
        then power(loc.latitude - p_latitude, 2) + power(loc.longitude - p_longitude, 2)
        else null
      end as gps_distance_score,
      case
        when p_area_id is not null
         and public.location_ancestor_id(l.location_id, 'area'::public.location_type) = p_area_id then 1
        when p_ward_id is not null
         and public.location_ancestor_id(l.location_id, 'ward'::public.location_type) = p_ward_id then 2
        when p_district_id is not null
         and public.location_ancestor_id(l.location_id, 'district'::public.location_type) = p_district_id then 3
        when p_region_id is not null
         and public.location_ancestor_id(l.location_id, 'region'::public.location_type) = p_region_id then 4
        when p_latitude is not null and p_longitude is not null then 5
        else 6
      end as priority_group,
      (
        ((('x' || substr(
          md5(coalesce(p_session_seed, to_char(current_date, 'YYYYMMDD')) || ':' || l.id::text),
          1,
          8
        ))::bit(32)::bigint)::numeric + 1)
      ) / 4294967296::numeric as random_unit,
      (
        p_region_id is not null
        or p_district_id is not null
        or p_ward_id is not null
        or p_area_id is not null
        or (p_latitude is not null and p_longitude is not null)
      ) as has_location_signal
    from public.listings l
    join public.agents a
      on a.id = l.agent_id
     and a.account_status = 'active'::public.agent_account_status
    join public.asset_categories c
      on c.id = l.category_id
     and c.is_active = true
    left join public.locations loc on loc.id = l.location_id
    left join public.listing_media lm
      on lm.listing_id = l.id
     and lm.is_cover = true
    where l.status = 'active'::public.listing_status
      and l.availability_status = 'available'::public.availability_status
      and l.removed_from_market_at is null
      and (
        p_category_slug is null
        or c.slug = p_category_slug
      )
      and (
        p_search_text is null
        or btrim(p_search_text) = ''
        or l.title ilike '%' || btrim(p_search_text) || '%'
        or l.description ilike '%' || btrim(p_search_text) || '%'
        or l.public_location_label ilike '%' || btrim(p_search_text) || '%'
        or c.name ilike '%' || btrim(p_search_text) || '%'
      )
  )
  select
    listing_id,
    title,
    public_location_label,
    price_amount,
    price_period,
    category_id,
    category_name,
    category_slug,
    category_icon_key,
    home_feed_weight,
    cover_storage_path,
    region_id,
    district_id
  from eligible
  order by
    case when has_location_signal then priority_group else 0 end asc,
    case when has_location_signal then gps_distance_score end nulls last,
    case when not has_location_signal then random_unit end asc nulls last,
    case
      when p_search_text is null or btrim(p_search_text) = '' then 0
      when title ilike btrim(p_search_text) || '%' then 0
      else 1
    end,
    freshness_at desc,
    listing_id
  offset greatest(coalesce(p_page, 0), 0) * greatest(least(coalesce(p_limit, 20), 50), 1)
  limit greatest(least(coalesce(p_limit, 20), 50), 1);
$$;

revoke all on function public.get_public_home_feed(
  integer,
  integer,
  uuid,
  uuid,
  uuid,
  uuid,
  double precision,
  double precision,
  text
) from public, anon, authenticated;
grant execute on function public.get_public_home_feed(
  integer,
  integer,
  uuid,
  uuid,
  uuid,
  uuid,
  double precision,
  double precision,
  text
) to anon, authenticated, service_role;

revoke all on function public.get_public_listings(
  text,
  text,
  uuid,
  uuid,
  uuid,
  uuid,
  integer,
  integer,
  double precision,
  double precision,
  text
) from public, anon, authenticated;
grant execute on function public.get_public_listings(
  text,
  text,
  uuid,
  uuid,
  uuid,
  uuid,
  integer,
  integer,
  double precision,
  double precision,
  text
) to anon, authenticated, service_role;
