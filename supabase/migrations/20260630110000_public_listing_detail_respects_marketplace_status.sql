drop function if exists public.get_public_listing_detail(uuid);

create or replace function public.get_public_listing_detail(p_listing_id uuid)
returns table (
  listing_id uuid,
  listing_location_id uuid,
  region_id uuid,
  district_id uuid,
  ward_id uuid,
  area_id uuid,
  title text,
  description text,
  public_location_label text,
  price_amount numeric,
  price_period text,
  listing_rules text,
  listing_attributes jsonb,
  category_id uuid,
  category_name text,
  category_slug text,
  category_field_schema jsonb,
  agent_id uuid,
  agent_display_name text,
  agent_business_name text,
  agent_phone_number text,
  agent_location_label text,
  agent_verification_status text,
  agent_verified_at timestamptz,
  agent_profile_photo_path text,
  media jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    l.id as listing_id,
    l.location_id as listing_location_id,
    public.location_ancestor_id(
      l.location_id,
      'region'::public.location_type
    ) as region_id,
    public.location_ancestor_id(
      l.location_id,
      'district'::public.location_type
    ) as district_id,
    public.location_ancestor_id(
      l.location_id,
      'ward'::public.location_type
    ) as ward_id,
    public.location_ancestor_id(
      l.location_id,
      'area'::public.location_type
    ) as area_id,
    l.title,
    l.description,
    l.public_location_label,
    l.price_amount,
    l.price_period::text as price_period,
    l.listing_rules,
    l.listing_attributes,
    c.id as category_id,
    c.name as category_name,
    c.slug as category_slug,
    c.field_schema as category_field_schema,
    a.id as agent_id,
    coalesce(
      nullif(btrim(a.display_name), ''),
      nullif(btrim(a.business_name), ''),
      'Agent'
    ) as agent_display_name,
    a.business_name as agent_business_name,
    null::text as agent_phone_number,
    a.public_location_label as agent_location_label,
    a.verification_status::text as agent_verification_status,
    a.verified_at as agent_verified_at,
    a.profile_photo_path as agent_profile_photo_path,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'storage_path', public.normalize_listing_media_path(lm.storage_path),
            'thumbnail_path', public.normalize_listing_media_path(lm.thumbnail_path),
            'media_type', lm.media_type::text,
            'is_cover', lm.is_cover,
            'display_order', lm.display_order
          )
          order by lm.display_order
        )
        from public.listing_media lm
        where lm.listing_id = l.id
      ),
      '[]'::jsonb
    ) as media
  from public.listings l
  join public.asset_categories c on c.id = l.category_id
  join public.agents a on a.id = l.agent_id
  where l.id = p_listing_id
    and public.is_listing_public(l.id);
$$;

revoke all on function public.get_public_listing_detail(uuid)
from public, anon, authenticated;

grant execute on function public.get_public_listing_detail(uuid)
to anon, authenticated, service_role;
