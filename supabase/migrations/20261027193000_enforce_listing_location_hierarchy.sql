-- Global marketplace location filters must narrow every category consistently.
-- The previous search only enforced region and used deeper levels for ranking.
create or replace function public.search_public_listings_v2(
  p_category_slug text, p_search_text text, p_region_id uuid,
  p_district_id uuid, p_ward_id uuid, p_area_id uuid, p_min_price numeric,
  p_max_price numeric, p_price_period text, p_sort text, p_limit integer,
  p_page integer, p_latitude double precision, p_longitude double precision,
  p_session_seed text
)
returns table (
  listing_id uuid, title text, public_location_label text, price_amount numeric,
  price_period text, availability_status text, category_id uuid,
  category_name text, category_slug text, category_icon_key text,
  home_feed_weight integer, cover_storage_path text, region_id uuid,
  district_id uuid, published_at timestamptz, total_count bigint
)
language sql stable security definer set search_path = public
as $$
  with detected as (
    select * from public.resolve_location_hierarchy(p_latitude, p_longitude)
    where p_latitude is not null and p_longitude is not null
  ), wanted as (
    select coalesce(p_region_id, d.region_id) region_id,
      coalesce(p_district_id, d.district_id) district_id,
      coalesce(p_ward_id, d.ward_id) ward_id,
      coalesce(p_area_id, d.area_id) area_id
    from (select 1) x left join detected d on true
  ), eligible as (
    select l.id listing_id, l.title, l.public_location_label, l.price_amount,
      l.price_period::text price_period, l.availability_status::text availability_status,
      c.id category_id, c.name category_name, c.slug category_slug, c.icon_key category_icon_key,
      c.home_feed_weight, public.normalize_listing_media_path(lm.storage_path) cover_storage_path,
      public.location_ancestor_id(l.location_id, 'region'::public.location_type) region_id,
      public.location_ancestor_id(l.location_id, 'district'::public.location_type) district_id,
      coalesce(l.published_at, l.created_at) published_at,
      ((('x' || substr(md5(coalesce(p_session_seed, to_char(current_date, 'YYYYMMDD')) || ':' || l.id::text), 1, 8))::bit(32)::bigint)::numeric + 1) / 4294967296::numeric random_unit
    from public.listings l
    join public.agents a on a.id = l.agent_id and a.account_status = 'active'::public.agent_account_status
    join public.asset_categories c on c.id = l.category_id and c.is_active = true
    left join public.listing_media lm on lm.listing_id = l.id and lm.is_cover = true
    cross join wanted w
    where l.status = 'active'::public.listing_status
      and l.availability_status = 'available'::public.availability_status
      and l.removed_from_market_at is null
      and (w.region_id is null or public.location_ancestor_id(l.location_id, 'region'::public.location_type) = w.region_id)
      and (w.district_id is null or public.location_ancestor_id(l.location_id, 'district'::public.location_type) = w.district_id)
      and (w.ward_id is null or public.location_ancestor_id(l.location_id, 'ward'::public.location_type) = w.ward_id)
      and (w.area_id is null or public.location_ancestor_id(l.location_id, 'area'::public.location_type) = w.area_id)
      and (p_category_slug is null or btrim(p_category_slug) = '' or c.slug = p_category_slug)
      and (p_min_price is null or l.price_amount >= greatest(p_min_price, 0))
      and (p_max_price is null or l.price_amount <= p_max_price)
      and (p_price_period is null or btrim(p_price_period) = '' or l.price_period::text = p_price_period)
      and (p_search_text is null or btrim(p_search_text) = '' or l.title ilike '%' || btrim(p_search_text) || '%'
        or l.description ilike '%' || btrim(p_search_text) || '%' or l.public_location_label ilike '%' || btrim(p_search_text) || '%'
        or c.name ilike '%' || btrim(p_search_text) || '%' or l.listing_attributes::text ilike '%' || btrim(p_search_text) || '%')
  ), counted as (select eligible.*, count(*) over () total_count from eligible)
  select listing_id, title, public_location_label, price_amount, price_period, availability_status,
    category_id, category_name, category_slug, category_icon_key, home_feed_weight, cover_storage_path,
    region_id, district_id, published_at, total_count
  from counted
  order by
    case when coalesce(p_sort, 'recommended') = 'price_low' then price_amount end asc nulls last,
    case when coalesce(p_sort, 'recommended') = 'price_high' then price_amount end desc nulls last,
    case when coalesce(p_sort, 'recommended') = 'newest' then published_at end desc nulls last,
    case when coalesce(p_sort, 'recommended') = 'recommended' then random_unit end asc nulls last,
    case when p_search_text is null or btrim(p_search_text) = '' then 0 when title ilike btrim(p_search_text) || '%' then 0 else 1 end,
    published_at desc, listing_id
  offset greatest(coalesce(p_page, 0), 0) * greatest(least(coalesce(p_limit, 20), 50), 1)
  limit greatest(least(coalesce(p_limit, 20), 50), 1);
$$;

revoke all on function public.search_public_listings_v2(text, text, uuid, uuid, uuid, uuid, numeric, numeric, text, text, integer, integer, double precision, double precision, text) from public;
grant execute on function public.search_public_listings_v2(text, text, uuid, uuid, uuid, uuid, numeric, numeric, text, text, integer, integer, double precision, double precision, text) to anon, authenticated, service_role;
