alter table public.platform_promotions
  add column if not exists target_region_id uuid references public.locations (id),
  add column if not exists target_district_id uuid references public.locations (id),
  add column if not exists target_ward_id uuid references public.locations (id),
  add column if not exists target_area_id uuid references public.locations (id);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'platform_promotions_target_location_depth_check'
      and conrelid = 'public.platform_promotions'::regclass
  ) then
    alter table public.platform_promotions
      add constraint platform_promotions_target_location_depth_check
      check (
        (target_region_id is not null or (
          target_district_id is null
          and target_ward_id is null
          and target_area_id is null
        ))
        and (target_district_id is not null or (
          target_ward_id is null
          and target_area_id is null
        ))
        and (target_ward_id is not null or target_area_id is null)
      );
  end if;
end
$$;

create or replace function public.validate_platform_promotion_target_location()
returns trigger
language plpgsql
as $$
declare
  v_region_type public.location_type;
  v_district_type public.location_type;
  v_ward_type public.location_type;
  v_area_type public.location_type;
begin
  if new.target_region_id is not null then
    select location_type
    into v_region_type
    from public.locations
    where id = new.target_region_id;

    if v_region_type is distinct from 'region'::public.location_type then
      raise exception 'Promotion target region must point to a region location';
    end if;
  end if;

  if new.target_district_id is not null then
    select location_type
    into v_district_type
    from public.locations
    where id = new.target_district_id;

    if v_district_type is distinct from 'district'::public.location_type then
      raise exception 'Promotion target district must point to a district location';
    end if;

    if public.location_ancestor_id(
      new.target_district_id,
      'region'::public.location_type
    ) is distinct from new.target_region_id then
      raise exception 'Promotion target district must belong to the selected region';
    end if;
  end if;

  if new.target_ward_id is not null then
    select location_type
    into v_ward_type
    from public.locations
    where id = new.target_ward_id;

    if v_ward_type is distinct from 'ward'::public.location_type then
      raise exception 'Promotion target ward must point to a ward location';
    end if;

    if public.location_ancestor_id(
      new.target_ward_id,
      'district'::public.location_type
    ) is distinct from new.target_district_id then
      raise exception 'Promotion target ward must belong to the selected district';
    end if;

    if public.location_ancestor_id(
      new.target_ward_id,
      'region'::public.location_type
    ) is distinct from new.target_region_id then
      raise exception 'Promotion target ward must belong to the selected region';
    end if;
  end if;

  if new.target_area_id is not null then
    select location_type
    into v_area_type
    from public.locations
    where id = new.target_area_id;

    if v_area_type is distinct from 'area'::public.location_type then
      raise exception 'Promotion target area must point to an area location';
    end if;

    if public.location_ancestor_id(
      new.target_area_id,
      'ward'::public.location_type
    ) is distinct from new.target_ward_id then
      raise exception 'Promotion target area must belong to the selected ward';
    end if;

    if public.location_ancestor_id(
      new.target_area_id,
      'district'::public.location_type
    ) is distinct from new.target_district_id then
      raise exception 'Promotion target area must belong to the selected district';
    end if;

    if public.location_ancestor_id(
      new.target_area_id,
      'region'::public.location_type
    ) is distinct from new.target_region_id then
      raise exception 'Promotion target area must belong to the selected region';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists validate_platform_promotion_target_location
on public.platform_promotions;

create trigger validate_platform_promotion_target_location
before insert or update on public.platform_promotions
for each row execute function public.validate_platform_promotion_target_location();

create index if not exists idx_platform_promotions_target_location
  on public.platform_promotions (
    target_region_id,
    target_district_id,
    target_ward_id,
    target_area_id
  );

create table if not exists public.listing_contact_payments (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  agent_id uuid not null references public.agents (id) on delete cascade,
  order_reference text not null unique,
  access_token text not null unique,
  payment_provider text not null default 'clickpesa',
  payment_status text not null default 'pending',
  requested_amount numeric(12, 2) not null,
  requested_currency text not null default 'TZS',
  customer_name text not null,
  customer_phone_number text not null,
  customer_email text,
  checkout_link text,
  provider_client_id text,
  provider_payment_id text,
  provider_payment_reference text,
  provider_channel text,
  status_message text,
  initiated_at timestamptz not null default timezone('utc', now()),
  paid_at timestamptz,
  failed_at timestamptz,
  contact_revealed_at timestamptz,
  last_status_checked_at timestamptz,
  checkout_payload jsonb not null default '{}'::jsonb,
  provider_response jsonb not null default '{}'::jsonb,
  webhook_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint listing_contact_payments_status_check
    check (payment_status in (
      'pending',
      'processing',
      'paid',
      'failed',
      'expired',
      'cancelled'
    ))
);

create index if not exists idx_listing_contact_payments_listing_id
  on public.listing_contact_payments (listing_id, payment_status, created_at desc);

create index if not exists idx_listing_contact_payments_order_reference
  on public.listing_contact_payments (order_reference);

alter table public.listing_contact_payments enable row level security;

drop trigger if exists set_listing_contact_payments_updated_at
on public.listing_contact_payments;

create trigger set_listing_contact_payments_updated_at
before update on public.listing_contact_payments
for each row execute function public.set_updated_at();

drop function if exists public.get_active_platform_promotions(text, text, integer);

create or replace function public.get_active_platform_promotions(
  p_surface text default 'customer_app',
  p_placement text default 'global',
  p_limit integer default 4,
  p_selected_region_id uuid default null,
  p_selected_district_id uuid default null,
  p_selected_ward_id uuid default null,
  p_selected_area_id uuid default null
)
returns table (
  promotion_id uuid,
  title text,
  description text,
  cta_label text,
  target_url text,
  placement text,
  visibility_scope text,
  media_type text,
  media_path text,
  thumbnail_path text
)
language sql
stable
security definer
set search_path = public
as $$
  with viewer as (
    select
      public.is_admin(auth.uid()) as is_admin,
      public.is_agent_active(auth.uid()) as is_active_agent,
      (
        select a.location_id
        from public.agents a
        where a.profile_id = auth.uid()
        order by a.created_at desc
        limit 1
      ) as agent_location_id
  ),
  selection as (
    select
      v.is_admin,
      v.is_active_agent,
      coalesce(
        p_selected_region_id,
        public.location_ancestor_id(v.agent_location_id, 'region'::public.location_type)
      ) as selected_region_id,
      coalesce(
        p_selected_district_id,
        public.location_ancestor_id(v.agent_location_id, 'district'::public.location_type)
      ) as selected_district_id,
      coalesce(
        p_selected_ward_id,
        public.location_ancestor_id(v.agent_location_id, 'ward'::public.location_type)
      ) as selected_ward_id,
      coalesce(
        p_selected_area_id,
        public.location_ancestor_id(v.agent_location_id, 'area'::public.location_type)
      ) as selected_area_id
    from viewer v
  )
  select
    p.id as promotion_id,
    p.title,
    p.description,
    p.cta_label,
    p.target_url,
    p.placement,
    p.visibility_scope,
    pm.media_type::text,
    pm.media_path,
    pm.thumbnail_path
  from public.platform_promotions p
  cross join selection s
  left join lateral (
    select media_type, media_path, thumbnail_path
    from public.platform_promotion_media
    where promotion_id = p.id
    order by is_primary desc, display_order asc, created_at asc
    limit 1
  ) pm on true
  where p.is_active = true
    and coalesce(p.start_at, timezone('utc', now())) <= timezone('utc', now())
    and coalesce(
      p.end_at,
      timezone('utc', now()) + interval '100 years'
    ) >= timezone('utc', now())
    and (p.placement = p_placement or p.placement = 'global')
    and (
      s.is_admin
      or (
        s.is_active_agent
        and p_placement in ('global', 'manage_dashboard')
        and p.placement in ('global', 'manage_dashboard')
      )
      or (
        not s.is_admin
        and not s.is_active_agent
        and p_placement in ('global', 'home_feed', 'category_page', 'listing_detail', 'website')
        and p.placement in ('global', 'home_feed', 'category_page', 'listing_detail', 'website')
      )
    )
    and (
      (not s.is_admin and not s.is_active_agent and p.visibility_scope in ('public', 'all'))
      or (s.is_active_agent and p.visibility_scope in ('public', 'manage', 'all'))
      or (s.is_admin and p.visibility_scope in ('public', 'manage', 'admin', 'all'))
    )
    and (
      s.is_admin
      or p.target_region_id is null
      or (
        p.target_region_id = s.selected_region_id
        and (
          p.target_district_id is null
          or p.target_district_id = s.selected_district_id
        )
        and (
          p.target_ward_id is null
          or p.target_ward_id = s.selected_ward_id
        )
        and (
          p.target_area_id is null
          or p.target_area_id = s.selected_area_id
        )
      )
    )
  order by
    case when p.placement = 'global' then 0 else 1 end,
    coalesce(p.start_at, p.created_at) desc,
    p.display_order asc,
    p.created_at desc
  limit greatest(p_limit, 1);
$$;

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
  where l.id = p_listing_id;
$$;

revoke all on function public.get_active_platform_promotions(
  text,
  text,
  integer,
  uuid,
  uuid,
  uuid,
  uuid
) from public, anon, authenticated;

grant execute on function public.get_active_platform_promotions(
  text,
  text,
  integer,
  uuid,
  uuid,
  uuid,
  uuid
) to anon, authenticated, service_role;

revoke all on function public.get_public_listing_detail(uuid)
from public, anon, authenticated;

grant execute on function public.get_public_listing_detail(uuid)
to anon, authenticated, service_role;
