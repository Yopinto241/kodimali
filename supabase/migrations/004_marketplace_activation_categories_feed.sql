begin;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typname = 'agent_account_status'
  ) then
    create type public.agent_account_status as enum (
      'inactive',
      'active',
      'suspended'
    );
  end if;
end
$$;

do $$
begin
  if exists (
    select 1
    from pg_trigger
    where tgname = 'guard_listing_workflow'
      and tgrelid = 'public.listings'::regclass
  ) then
    alter table public.listings disable trigger guard_listing_workflow;
  end if;
end
$$;

alter table public.agents
  add column if not exists account_status public.agent_account_status,
  add column if not exists activated_at timestamptz,
  add column if not exists deactivated_at timestamptz,
  add column if not exists deactivation_reason text,
  add column if not exists business_description text;

alter table public.agents
  alter column account_status set default 'inactive'::public.agent_account_status;

update public.agents
set
  account_status = 'inactive'::public.agent_account_status,
  activated_at = null,
  deactivated_at = null,
  deactivation_reason = null
where account_status is distinct from 'inactive'::public.agent_account_status
   or activated_at is not null
   or deactivated_at is not null
   or deactivation_reason is not null;

alter table public.agents
  alter column account_status set not null;

create or replace function public.current_agent_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
  from public.agents
  where profile_id = auth.uid()
  limit 1;
$$;

create or replace function public.current_agent_context()
returns table (
  id uuid,
  profile_id uuid,
  account_status text,
  verification_status text,
  business_name text,
  business_description text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    a.id,
    a.profile_id,
    a.account_status::text,
    a.verification_status::text,
    a.business_name,
    a.business_description
  from public.agents a
  where a.profile_id = auth.uid()
  limit 1;
$$;

create or replace function public.get_my_agent_status()
returns table (
  id uuid,
  profile_id uuid,
  business_name text,
  account_status text,
  verification_status text,
  activated_at timestamptz,
  deactivated_at timestamptz,
  deactivation_reason text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    a.id,
    a.profile_id,
    a.business_name,
    a.account_status::text,
    a.verification_status::text,
    a.activated_at,
    a.deactivated_at,
    a.deactivation_reason
  from public.agents a
  where a.profile_id = auth.uid()
  limit 1;
$$;

create or replace function public.submit_agent_application(
  p_business_name text,
  p_business_description text default null,
  p_phone_number text default null
)
returns table (
  agent_id uuid,
  profile_id uuid,
  account_status text,
  verification_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_existing_agent public.agents%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if coalesce(btrim(p_business_name), '') = '' then
    raise exception 'Business name is required';
  end if;

  if coalesce(btrim(p_phone_number), '') <> '' then
    update public.profiles
    set phone_number = btrim(p_phone_number)
    where id = v_user_id;
  end if;

  insert into public.user_roles (profile_id, role)
  values (v_user_id, 'agent'::public.app_role)
  on conflict (profile_id, role) do nothing;

  select *
  into v_existing_agent
  from public.agents
  where profile_id = v_user_id
  limit 1;

  if v_existing_agent.id is null then
    insert into public.agents (
      profile_id,
      business_name,
      business_description
    )
    values (
      v_user_id,
      btrim(p_business_name),
      nullif(btrim(p_business_description), '')
    );
  end if;

  return query
  select
    a.id as agent_id,
    a.profile_id,
    a.account_status::text,
    a.verification_status::text
  from public.agents a
  where a.profile_id = v_user_id
  limit 1;
end;
$$;

create or replace function public.is_agent_active(check_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.agents
    where profile_id = check_user
      and account_status = 'active'::public.agent_account_status
  );
$$;

create or replace function public.can_manage_agent_documents(check_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.agents
    where profile_id = check_user
      and account_status = 'inactive'::public.agent_account_status
      and verification_status = 'pending'::public.agent_verification_status
  );
$$;

create or replace function public.can_access_manage_session(check_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin(check_user)
    or public.is_agent_active(check_user);
$$;

create or replace function public.update_my_agent_profile(
  p_business_name text,
  p_business_description text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_agent_active() then
    raise exception 'Only active agents can update agent profile details';
  end if;

  if coalesce(btrim(p_business_name), '') = '' then
    raise exception 'Business name is required';
  end if;

  update public.agents
  set
    business_name = btrim(p_business_name),
    business_description = nullif(btrim(p_business_description), '')
  where profile_id = auth.uid();
end;
$$;

create or replace function public.guard_agent_account_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if public.is_admin(auth.uid()) then
      new.account_status := coalesce(
        new.account_status,
        'inactive'::public.agent_account_status
      );
      if new.account_status = 'active'::public.agent_account_status then
        new.activated_at := coalesce(new.activated_at, timezone('utc', now()));
        new.deactivated_at := null;
        new.deactivation_reason := null;
      else
        new.activated_at := null;
      end if;
      return new;
    end if;

    new.account_status := 'inactive'::public.agent_account_status;
    new.activated_at := null;
    new.deactivated_at := null;
    new.deactivation_reason := null;
    new.verification_status := coalesce(
      new.verification_status,
      'pending'::public.agent_verification_status
    );
    new.verified_at := null;
    new.admin_notes := null;
    new.average_response_minutes := null;
    return new;
  end if;

  if public.is_admin(auth.uid()) then
    if new.account_status = 'active'::public.agent_account_status then
      new.activated_at := coalesce(new.activated_at, old.activated_at, timezone('utc', now()));
      new.deactivated_at := null;
      new.deactivation_reason := null;
    else
      new.activated_at := null;
      new.deactivated_at := coalesce(new.deactivated_at, timezone('utc', now()));
    end if;
    return new;
  end if;

  if old.profile_id is distinct from auth.uid() then
    raise exception 'Agents can update only their own safe profile fields';
  end if;

  if old.account_status <> 'active'::public.agent_account_status then
    raise exception 'Inactive or suspended agents cannot update agent records';
  end if;

  if new.profile_id is distinct from old.profile_id
    or new.account_status is distinct from old.account_status
    or new.activated_at is distinct from old.activated_at
    or new.deactivated_at is distinct from old.deactivated_at
    or new.deactivation_reason is distinct from old.deactivation_reason
    or new.verification_status is distinct from old.verification_status
    or new.verified_at is distinct from old.verified_at
    or new.admin_notes is distinct from old.admin_notes
    or new.average_response_minutes is distinct from old.average_response_minutes
  then
    raise exception 'Agents cannot update protected agent-account fields';
  end if;

  new.profile_id := old.profile_id;
  new.account_status := old.account_status;
  new.activated_at := old.activated_at;
  new.deactivated_at := old.deactivated_at;
  new.deactivation_reason := old.deactivation_reason;
  new.verification_status := old.verification_status;
  new.verified_at := old.verified_at;
  new.admin_notes := old.admin_notes;
  new.average_response_minutes := old.average_response_minutes;

  return new;
end;
$$;

drop trigger if exists protect_agent_verification_fields on public.agents;
drop trigger if exists guard_agent_account_update on public.agents;
create trigger guard_agent_account_update
before insert or update on public.agents
for each row execute function public.guard_agent_account_update();

create table if not exists public.asset_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  description text,
  icon_key text,
  display_order integer not null default 0,
  is_active boolean not null default true,
  home_feed_weight integer not null default 1,
  field_schema jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.listing_private_locations (
  listing_id uuid primary key references public.listings (id) on delete cascade,
  exact_address text,
  map_pin_latitude numeric(10, 7),
  map_pin_longitude numeric(10, 7),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'listings'
      and column_name = 'exact_address'
  ) then
    insert into public.listing_private_locations (
      listing_id,
      exact_address,
      map_pin_latitude,
      map_pin_longitude
    )
    select
      l.id,
      nullif(btrim(l.exact_address), ''),
      l.map_pin_latitude,
      l.map_pin_longitude
    from public.listings l
    where nullif(btrim(l.exact_address), '') is not null
       or l.map_pin_latitude is not null
       or l.map_pin_longitude is not null
    on conflict (listing_id) do update
    set
      exact_address = excluded.exact_address,
      map_pin_latitude = excluded.map_pin_latitude,
      map_pin_longitude = excluded.map_pin_longitude,
      updated_at = timezone('utc', now());

    update public.listings
    set
      exact_address = null,
      map_pin_latitude = null,
      map_pin_longitude = null
    where exact_address is not null
       or map_pin_latitude is not null
       or map_pin_longitude is not null;

    alter table public.listings drop column if exists exact_address;
    alter table public.listings drop column if exists map_pin_latitude;
    alter table public.listings drop column if exists map_pin_longitude;
  end if;
end
$$;

create table if not exists public.farm_details (
  listing_id uuid primary key references public.listings (id) on delete cascade,
  water_availability text,
  soil_type text,
  best_crops text[],
  land_size numeric(12, 2),
  land_size_unit text,
  irrigation_available boolean,
  access_road boolean,
  electricity_available boolean,
  fencing boolean,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

drop trigger if exists set_asset_categories_updated_at on public.asset_categories;
create trigger set_asset_categories_updated_at
before update on public.asset_categories
for each row execute procedure public.set_updated_at();

drop trigger if exists set_listing_private_locations_updated_at on public.listing_private_locations;
create trigger set_listing_private_locations_updated_at
before update on public.listing_private_locations
for each row execute procedure public.set_updated_at();

drop trigger if exists set_farm_details_updated_at on public.farm_details;
create trigger set_farm_details_updated_at
before update on public.farm_details
for each row execute procedure public.set_updated_at();

alter table public.asset_categories enable row level security;
alter table public.listing_private_locations enable row level security;
alter table public.farm_details enable row level security;

drop policy if exists "asset_categories_active_select" on public.asset_categories;
create policy "asset_categories_active_select"
on public.asset_categories
for select
using (is_active or public.is_admin());

drop policy if exists "asset_categories_admin_all" on public.asset_categories;
create policy "asset_categories_admin_all"
on public.asset_categories
for all
using (public.is_admin())
with check (public.is_admin());

insert into public.asset_categories (
  name,
  slug,
  description,
  icon_key,
  display_order,
  is_active,
  home_feed_weight,
  field_schema
)
values
  (
    'House',
    'house',
    'Nyumba za kuishi au kupangisha.',
    'house',
    1,
    true,
    10,
    '[
      {"key":"bedrooms","label":"Bedrooms","type":"number"},
      {"key":"bathrooms","label":"Bathrooms","type":"number"},
      {"key":"furnished","label":"Furnished","type":"boolean"},
      {"key":"parking","label":"Parking","type":"boolean"}
    ]'::jsonb
  ),
  (
    'Car',
    'car',
    'Magari ya kukodi au huduma za usafiri.',
    'car',
    2,
    true,
    4,
    '[
      {"key":"brand","label":"Brand","type":"text"},
      {"key":"model","label":"Model","type":"text"},
      {"key":"year","label":"Year","type":"number"},
      {"key":"driver_included","label":"Driver included","type":"boolean"}
    ]'::jsonb
  ),
  (
    'Motorcycle',
    'motorcycle',
    'Pikipiki za kukodi au usafirishaji.',
    'motorcycle',
    3,
    true,
    3,
    '[
      {"key":"brand","label":"Brand","type":"text"},
      {"key":"model","label":"Model","type":"text"},
      {"key":"year","label":"Year","type":"number"},
      {"key":"helmet_included","label":"Helmet included","type":"boolean"}
    ]'::jsonb
  ),
  (
    'Office',
    'office',
    'Ofisi, nafasi za biashara, na maeneo ya kazi.',
    'office',
    4,
    true,
    2,
    '[
      {"key":"size_sqm","label":"Size sqm","type":"number"},
      {"key":"parking","label":"Parking","type":"boolean"},
      {"key":"internet_available","label":"Internet available","type":"boolean"}
    ]'::jsonb
  ),
  (
    'Meeting Hall',
    'meeting-hall',
    'Kumbi za mikutano na semina.',
    'meeting_hall',
    5,
    true,
    2,
    '[
      {"key":"capacity","label":"Capacity","type":"number"},
      {"key":"chairs_available","label":"Chairs","type":"number"},
      {"key":"projector","label":"Projector","type":"boolean"}
    ]'::jsonb
  ),
  (
    'Ceremony Hall',
    'ceremony-hall',
    'Kumbi za sherehe na matukio.',
    'celebration',
    6,
    true,
    2,
    '[
      {"key":"capacity","label":"Capacity","type":"number"},
      {"key":"sound_system","label":"Sound system","type":"boolean"},
      {"key":"kitchen","label":"Kitchen","type":"boolean"}
    ]'::jsonb
  ),
  (
    'Equipment',
    'equipment',
    'Mashine, vifaa, na tools.',
    'inventory_2',
    7,
    true,
    1,
    '[
      {"key":"condition","label":"Condition","type":"text"},
      {"key":"delivery_available","label":"Delivery available","type":"boolean"}
    ]'::jsonb
  ),
  (
    'Farms',
    'farms',
    'Mashamba ya kilimo, ufugaji, na matumizi ya kilimo.',
    'agriculture',
    8,
    true,
    2,
    '[
      {"key":"water_availability","label":"Water availability","type":"text"},
      {"key":"soil_type","label":"Soil type","type":"text"},
      {"key":"best_crops","label":"Best crops","type":"textarea"},
      {"key":"land_size","label":"Land size","type":"number"},
      {"key":"land_size_unit","label":"Land size unit","type":"select","options":["acre","hectare","sqm"]},
      {"key":"irrigation_available","label":"Irrigation available","type":"boolean"},
      {"key":"access_road","label":"Access road","type":"boolean"},
      {"key":"electricity_available","label":"Electricity available","type":"boolean"},
      {"key":"fencing","label":"Fencing","type":"boolean"}
    ]'::jsonb
  ),
  (
    'Other Asset',
    'other-asset',
    'Mali nyingine zisizoingia kwenye makundi ya awali.',
    'category',
    9,
    true,
    1,
    '[
      {"key":"specification","label":"Specification","type":"text"},
      {"key":"notes","label":"Notes","type":"textarea"}
    ]'::jsonb
  )
on conflict (slug) do update
set
  name = excluded.name,
  description = excluded.description,
  icon_key = excluded.icon_key,
  display_order = excluded.display_order,
  is_active = excluded.is_active,
  home_feed_weight = excluded.home_feed_weight,
  field_schema = excluded.field_schema;

alter table public.listings
  add column if not exists category_id uuid references public.asset_categories (id) on delete restrict,
  add column if not exists listing_attributes jsonb not null default '{}'::jsonb,
  add column if not exists removed_from_market_at timestamptz,
  add column if not exists removed_reason text;

create index if not exists idx_asset_categories_active_order
  on public.asset_categories (is_active, display_order, name);

create index if not exists idx_listings_category_id
  on public.listings (category_id);

create index if not exists idx_listings_public_eligibility
  on public.listings (
    status,
    availability_status,
    removed_from_market_at,
    category_id,
    agent_id
  );

create or replace function public.normalize_listing_media_path(check_path text)
returns text
language sql
immutable
as $$
  select case
    when check_path is null then null
    else regexp_replace(check_path, '^listing-media/', '')
  end;
$$;

create or replace function public.legacy_category_slug(check_category public.listing_category)
returns text
language sql
immutable
as $$
  select case check_category
    when 'house'::public.listing_category then 'house'
    when 'car'::public.listing_category then 'car'
    when 'motorcycle'::public.listing_category then 'motorcycle'
    when 'office'::public.listing_category then 'office'
    when 'meeting_hall'::public.listing_category then 'meeting-hall'
    when 'ceremony_hall'::public.listing_category then 'ceremony-hall'
    when 'equipment'::public.listing_category then 'equipment'
    else 'other-asset'
  end;
$$;

create or replace function public.legacy_listing_category_from_slug(check_slug text)
returns public.listing_category
language sql
immutable
as $$
  select case lower(coalesce(check_slug, ''))
    when 'house' then 'house'::public.listing_category
    when 'car' then 'car'::public.listing_category
    when 'motorcycle' then 'motorcycle'::public.listing_category
    when 'office' then 'office'::public.listing_category
    when 'meeting-hall' then 'meeting_hall'::public.listing_category
    when 'meeting_hall' then 'meeting_hall'::public.listing_category
    when 'ceremony-hall' then 'ceremony_hall'::public.listing_category
    when 'ceremony_hall' then 'ceremony_hall'::public.listing_category
    when 'equipment' then 'equipment'::public.listing_category
    when 'other-asset' then 'other_asset'::public.listing_category
    when 'other_asset' then 'other_asset'::public.listing_category
    else 'other_asset'::public.listing_category
  end;
$$;

create or replace function public.listing_category_from_category_id(check_category_id uuid)
returns public.listing_category
language sql
stable
as $$
  select coalesce(
    (
      select case
        when slug in (
          'house',
          'car',
          'motorcycle',
          'office',
          'meeting-hall',
          'meeting_hall',
          'ceremony-hall',
          'ceremony_hall',
          'equipment'
        ) then public.legacy_listing_category_from_slug(slug)
        else 'other_asset'::public.listing_category
      end
      from public.asset_categories
      where id = check_category_id
    ),
    'other_asset'::public.listing_category
  );
$$;

create or replace function public.listing_category_id_from_legacy(check_category public.listing_category)
returns uuid
language sql
stable
as $$
  select id
  from public.asset_categories
  where slug = public.legacy_category_slug(check_category)
  limit 1;
$$;

create or replace function public.location_ancestor_id(
  check_location_id uuid,
  target_location_type public.location_type
)
returns uuid
language sql
stable
as $$
  with recursive location_chain as (
    select loc.id, loc.parent_id, loc.location_type
    from public.locations loc
    where loc.id = check_location_id
    union all
    select parent.id, parent.parent_id, parent.location_type
    from location_chain
    join public.locations parent on parent.id = location_chain.parent_id
  )
  select id
  from location_chain
  where location_type = target_location_type
  limit 1;
$$;

create or replace function public.location_ancestor_name(
  check_location_id uuid,
  target_location_type public.location_type
)
returns text
language sql
stable
as $$
  select name
  from public.locations
  where id = public.location_ancestor_id(check_location_id, target_location_type);
$$;

create or replace function public.is_valid_listing_location(check_location_id uuid)
returns boolean
language plpgsql
stable
as $$
declare
  v_location public.locations%rowtype;
  v_area public.locations%rowtype;
  v_parent public.locations%rowtype;
begin
  if check_location_id is null then
    return false;
  end if;

  select *
  into v_location
  from public.locations
  where id = check_location_id
    and is_active = true;

  if v_location.id is null then
    return false;
  end if;

  if v_location.location_type = 'street'::public.location_type then
    select *
    into v_area
    from public.locations
    where id = v_location.parent_id
      and is_active = true;
    if v_area.id is null or v_area.location_type <> 'area'::public.location_type then
      return false;
    end if;
  elsif v_location.location_type = 'area'::public.location_type then
    v_area := v_location;
  else
    return false;
  end if;

  select *
  into v_parent
  from public.locations
  where id = v_area.parent_id
    and is_active = true;

  if v_parent.id is null then
    return false;
  end if;

  if v_parent.location_type = 'ward'::public.location_type then
    if public.location_ancestor_id(v_parent.id, 'district'::public.location_type) is null then
      return false;
    end if;
  elsif v_parent.location_type <> 'district'::public.location_type then
    return false;
  end if;

  return public.location_ancestor_id(check_location_id, 'region'::public.location_type) is not null
    and public.location_ancestor_id(check_location_id, 'district'::public.location_type) is not null
    and public.location_ancestor_id(check_location_id, 'area'::public.location_type) is not null;
end;
$$;

create or replace function public.build_public_location_label(check_location_id uuid)
returns text
language plpgsql
stable
as $$
declare
  v_region_name text;
  v_area_name text;
  v_district_name text;
begin
  if check_location_id is null then
    return null;
  end if;

  v_region_name := public.location_ancestor_name(check_location_id, 'region'::public.location_type);
  v_area_name := public.location_ancestor_name(check_location_id, 'area'::public.location_type);
  v_district_name := public.location_ancestor_name(check_location_id, 'district'::public.location_type);

  if v_area_name is not null and v_region_name is not null then
    return concat_ws(', ', v_area_name, v_region_name);
  end if;

  if v_district_name is not null and v_region_name is not null then
    return concat_ws(', ', v_district_name, v_region_name);
  end if;

  return coalesce(v_area_name, v_district_name, v_region_name);
end;
$$;

create or replace function public.sanitize_listing_attributes(
  p_category_id uuid,
  p_attributes jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_schema jsonb;
  v_field jsonb;
  v_key text;
  v_value jsonb;
  v_type text;
  v_text text;
  v_result jsonb := '{}'::jsonb;
  v_private_keys text[] := array[
    'exact_address',
    'address',
    'phone',
    'phone_number',
    'owner',
    'owner_name',
    'agent',
    'agent_phone',
    'latitude',
    'longitude',
    'map_pin_latitude',
    'map_pin_longitude',
    'gps'
  ];
begin
  if p_attributes is null then
    return '{}'::jsonb;
  end if;

  if jsonb_typeof(p_attributes) <> 'object' then
    raise exception 'listing_attributes must be a JSON object';
  end if;

  select field_schema
  into v_schema
  from public.asset_categories
  where id = p_category_id;

  if v_schema is null then
    raise exception 'Unknown category_id for listing attributes';
  end if;

  for v_key, v_value in
    select key, value
    from jsonb_each(p_attributes)
  loop
    if lower(v_key) = any (v_private_keys) then
      raise exception 'Private attribute key "%" is not allowed', v_key;
    end if;

    select item
    into v_field
    from jsonb_array_elements(v_schema) item
    where item ->> 'key' = v_key
    limit 1;

    if v_field is null then
      raise exception 'Unknown listing attribute key "%" for this category', v_key;
    end if;

    v_type := coalesce(v_field ->> 'type', 'text');
    v_text := btrim(v_value #>> '{}');

    case v_type
      when 'text', 'textarea' then
        if jsonb_typeof(v_value) in ('object', 'array') then
          raise exception 'Attribute "%" must be scalar text', v_key;
        end if;
        if v_text <> '' then
          v_result := v_result || jsonb_build_object(v_key, v_text);
        end if;

      when 'number' then
        if v_text !~ '^-?[0-9]+(\.[0-9]+)?$' then
          raise exception 'Attribute "%" must be numeric', v_key;
        end if;
        v_result := v_result || jsonb_build_object(v_key, (v_text)::numeric);

      when 'boolean' then
        if jsonb_typeof(v_value) = 'boolean' then
          v_result := v_result || jsonb_build_object(v_key, (v_value #>> '{}')::boolean);
        elsif lower(v_text) in ('true', 'false') then
          v_result := v_result || jsonb_build_object(v_key, v_text::boolean);
        else
          raise exception 'Attribute "%" must be boolean', v_key;
        end if;

      when 'select' then
        if not exists (
          select 1
          from jsonb_array_elements_text(coalesce(v_field -> 'options', '[]'::jsonb)) option_value
          where option_value = v_text
        ) then
          raise exception 'Attribute "%" must match one of the configured options', v_key;
        end if;
        v_result := v_result || jsonb_build_object(v_key, v_text);

      else
        raise exception 'Unsupported field_schema type "%" for key "%"', v_type, v_key;
    end case;
  end loop;

  return v_result;
end;
$$;

update public.listings l
set category_id = public.listing_category_id_from_legacy(l.category)
where l.category_id is null;

update public.listings l
set
  category = public.listing_category_from_category_id(l.category_id),
  public_location_label = public.build_public_location_label(l.location_id),
  listing_attributes = public.sanitize_listing_attributes(
    l.category_id,
    coalesce(l.listing_attributes, '{}'::jsonb)
  ),
  approval_status = 'approved'::public.approval_status
where l.category_id is not null
  and l.location_id is not null;

update public.listing_media
set
  storage_path = public.normalize_listing_media_path(storage_path),
  thumbnail_path = public.normalize_listing_media_path(thumbnail_path)
where storage_path like 'listing-media/%'
   or thumbnail_path like 'listing-media/%';

alter table public.listings
  alter column category_id set not null;

drop index if exists idx_listing_media_cover_one_per_listing;
create unique index idx_listing_media_cover_one_per_listing
  on public.listing_media (listing_id)
  where is_cover = true;

create or replace function public.sync_farm_details_from_listing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_category_slug text;
  v_best_crops text[];
begin
  select slug
  into v_category_slug
  from public.asset_categories
  where id = new.category_id;

  if v_category_slug <> 'farms' then
    delete from public.farm_details
    where listing_id = new.id;
    return new;
  end if;

  if jsonb_typeof(new.listing_attributes -> 'best_crops') = 'array' then
    select array_agg(value)
    into v_best_crops
    from jsonb_array_elements_text(new.listing_attributes -> 'best_crops') as value;
  elsif coalesce(btrim(new.listing_attributes ->> 'best_crops'), '') <> '' then
    v_best_crops := regexp_split_to_array(
      new.listing_attributes ->> 'best_crops',
      '\s*,\s*'
    );
  else
    v_best_crops := null;
  end if;

  insert into public.farm_details (
    listing_id,
    water_availability,
    soil_type,
    best_crops,
    land_size,
    land_size_unit,
    irrigation_available,
    access_road,
    electricity_available,
    fencing
  )
  values (
    new.id,
    nullif(btrim(new.listing_attributes ->> 'water_availability'), ''),
    nullif(btrim(new.listing_attributes ->> 'soil_type'), ''),
    v_best_crops,
    case
      when coalesce(new.listing_attributes ->> 'land_size', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
        then (new.listing_attributes ->> 'land_size')::numeric
      else null
    end,
    nullif(btrim(new.listing_attributes ->> 'land_size_unit'), ''),
    case
      when new.listing_attributes ? 'irrigation_available'
        then (new.listing_attributes ->> 'irrigation_available')::boolean
      else null
    end,
    case
      when new.listing_attributes ? 'access_road'
        then (new.listing_attributes ->> 'access_road')::boolean
      else null
    end,
    case
      when new.listing_attributes ? 'electricity_available'
        then (new.listing_attributes ->> 'electricity_available')::boolean
      else null
    end,
    case
      when new.listing_attributes ? 'fencing'
        then (new.listing_attributes ->> 'fencing')::boolean
      else null
    end
  )
  on conflict (listing_id) do update
  set
    water_availability = excluded.water_availability,
    soil_type = excluded.soil_type,
    best_crops = excluded.best_crops,
    land_size = excluded.land_size,
    land_size_unit = excluded.land_size_unit,
    irrigation_available = excluded.irrigation_available,
    access_road = excluded.access_road,
    electricity_available = excluded.electricity_available,
    fencing = excluded.fencing,
    updated_at = timezone('utc', now());

  return new;
end;
$$;

drop trigger if exists sync_farm_details_from_listing on public.listings;
create trigger sync_farm_details_from_listing
after insert or update of category_id, listing_attributes on public.listings
for each row execute function public.sync_farm_details_from_listing();

create or replace function public.is_listing_public(check_listing_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.listings l
    join public.agents a on a.id = l.agent_id
    join public.asset_categories c on c.id = l.category_id
    where l.id = check_listing_id
      and l.approval_status = 'approved'::public.approval_status
      and l.status = 'active'::public.listing_status
      and l.availability_status = 'available'::public.availability_status
      and l.removed_from_market_at is null
      and a.account_status = 'active'::public.agent_account_status
      and c.is_active = true
  );
$$;

create or replace function public.is_public_listing_media_object(check_object_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.listing_media lm
    where (
      lm.storage_path = check_object_name
      or lm.thumbnail_path = check_object_name
      or lm.storage_path = replace(check_object_name, 'listing-media/', '')
      or lm.thumbnail_path = replace(check_object_name, 'listing-media/', '')
      or 'listing-media/' || lm.storage_path = check_object_name
      or 'listing-media/' || lm.thumbnail_path = check_object_name
    )
      and public.is_listing_public(lm.listing_id)
  );
$$;

create or replace function public.viewer_can_access_promotion(
  p_visibility_scope text,
  p_placement text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with viewer as (
    select
      public.is_admin(auth.uid()) as is_admin,
      public.is_agent_active(auth.uid()) as is_active_agent
  )
  select case
    when viewer.is_admin then p_visibility_scope in ('public', 'manage', 'admin', 'all')
    when viewer.is_active_agent then
      p_visibility_scope in ('public', 'manage', 'all')
      and p_placement in ('global', 'manage_dashboard')
    else
      p_visibility_scope in ('public', 'all')
      and p_placement in ('global', 'home_feed', 'category_page', 'listing_detail', 'website')
  end
  from viewer;
$$;

create or replace function public.can_access_promotion_media_object(check_object_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.platform_promotions p
    join public.platform_promotion_media pm on pm.promotion_id = p.id
    where (
      pm.media_path = check_object_name
      or pm.thumbnail_path = check_object_name
    )
      and p.is_active = true
      and coalesce(p.start_at, timezone('utc', now())) <= timezone('utc', now())
      and coalesce(p.end_at, timezone('utc', now()) + interval '100 years') >= timezone('utc', now())
      and public.viewer_can_access_promotion(p.visibility_scope, p.placement)
  );
$$;

create or replace view public.listing_inquiry_counts
with (security_invoker = true) as
select
  listing_id,
  count(*)::bigint as inquiry_count
from public.booking_requests
group by listing_id;

revoke all on public.listing_inquiry_counts from public, anon, authenticated;
grant select on public.listing_inquiry_counts to service_role;

create or replace function public.get_listing_inquiry_counts(
  p_listing_ids uuid[] default null
)
returns table (
  listing_id uuid,
  inquiry_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with permitted_listings as (
    select l.id
    from public.listings l
    where public.is_admin(auth.uid())
       or (
         public.is_agent_active()
         and exists (
           select 1
           from public.agents a
           where a.id = l.agent_id
             and a.profile_id = auth.uid()
             and a.account_status = 'active'::public.agent_account_status
         )
       )
      and (
        p_listing_ids is null
        or l.id = any (p_listing_ids)
      )
  )
  select
    br.listing_id,
    count(*)::bigint as inquiry_count
  from public.booking_requests br
  join permitted_listings pl on pl.id = br.listing_id
  group by br.listing_id;
$$;

alter table public.booking_requests
  alter column customer_id drop not null,
  alter column requested_start_at drop not null,
  alter column requested_end_at drop not null;

alter table public.booking_requests
  add column if not exists customer_name text,
  add column if not exists customer_phone_number text,
  add column if not exists request_reference text;

alter table public.listings
  drop constraint if exists booking_requests_no_confirmed_overlap;

drop trigger if exists prepare_booking_request on public.booking_requests;
drop trigger if exists guard_booking_request_update on public.booking_requests;
drop trigger if exists record_booking_status_history on public.booking_requests;
drop trigger if exists create_booking_notification_records on public.booking_requests;
drop trigger if exists prepare_guest_booking_request on public.booking_requests;
drop trigger if exists guard_guest_booking_request_update on public.booking_requests;
drop trigger if exists record_guest_booking_status_history on public.booking_requests;
drop trigger if exists create_guest_booking_notification on public.booking_requests;

drop function if exists public.prepare_booking_request();
drop function if exists public.guard_booking_request_update();
drop function if exists public.record_booking_status_history();
drop function if exists public.create_booking_notification_records();
drop function if exists public.prepare_guest_booking_request();
drop function if exists public.guard_guest_booking_request_update();
drop function if exists public.record_guest_booking_status_history();
drop function if exists public.create_guest_booking_notification();

create sequence if not exists public.booking_request_reference_seq;

create or replace function public.generate_booking_request_reference()
returns text
language plpgsql
as $$
declare
  next_number bigint;
begin
  next_number := nextval('public.booking_request_reference_seq');
  return format(
    'KDM-%s-%s',
    to_char(timezone('utc', now()), 'YYYY'),
    lpad(next_number::text, 6, '0')
  );
end;
$$;

create or replace function public.prepare_guest_booking_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_listing public.listings%rowtype;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;

  if new.customer_name is null or btrim(new.customer_name) = '' then
    raise exception 'customer_name is required';
  end if;

  if new.customer_phone_number is null or btrim(new.customer_phone_number) = '' then
    raise exception 'customer_phone_number is required';
  end if;

  select *
  into v_listing
  from public.listings
  where id = new.listing_id;

  if v_listing.id is null then
    raise exception 'Listing was not found';
  end if;

  if not public.is_listing_public(new.listing_id) then
    raise exception 'Listing is not accepting public requests';
  end if;

  if exists (
    select 1
    from public.booking_requests br
    where br.listing_id = new.listing_id
      and br.customer_phone_number = new.customer_phone_number
      and br.created_at >= timezone('utc', now()) - interval '10 minutes'
  ) then
    raise exception 'A recent request from this phone number already exists for this listing';
  end if;

  new.customer_id := null;
  new.agent_id := v_listing.agent_id;
  new.requested_start_at := null;
  new.requested_end_at := null;
  new.request_message := null;
  new.booking_status := 'new'::public.booking_status;
  new.request_reference := coalesce(
    new.request_reference,
    public.generate_booking_request_reference()
  );

  return new;
end;
$$;

create or replace function public.guard_guest_booking_request_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agent_id uuid;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if public.is_admin(auth.uid()) then
    if new.listing_id is distinct from old.listing_id
      or new.agent_id is distinct from old.agent_id
      or new.customer_id is distinct from old.customer_id
      or new.customer_name is distinct from old.customer_name
      or new.customer_phone_number is distinct from old.customer_phone_number
      or new.request_reference is distinct from old.request_reference
      or new.requested_start_at is distinct from old.requested_start_at
      or new.requested_end_at is distinct from old.requested_end_at
    then
      raise exception 'Admin cannot change immutable guest-request fields';
    end if;
  else
    select a.id
    into v_agent_id
    from public.agents a
    where a.profile_id = auth.uid()
      and a.account_status = 'active'::public.agent_account_status
    limit 1;

    if v_agent_id is null or v_agent_id <> old.agent_id then
      raise exception 'Only the assigned active agent can update this request';
    end if;

    if new.listing_id is distinct from old.listing_id
      or new.agent_id is distinct from old.agent_id
      or new.customer_id is distinct from old.customer_id
      or new.customer_name is distinct from old.customer_name
      or new.customer_phone_number is distinct from old.customer_phone_number
      or new.request_reference is distinct from old.request_reference
      or new.requested_start_at is distinct from old.requested_start_at
      or new.requested_end_at is distinct from old.requested_end_at
      or new.admin_override is distinct from old.admin_override
    then
      raise exception 'Active agents can update only guest inquiry status fields';
    end if;
  end if;

  new.customer_id := null;
  new.listing_id := old.listing_id;
  new.agent_id := old.agent_id;
  new.customer_name := old.customer_name;
  new.customer_phone_number := old.customer_phone_number;
  new.request_reference := old.request_reference;
  new.requested_start_at := null;
  new.requested_end_at := null;

  if new.booking_status is distinct from old.booking_status
     and old.first_agent_response_at is null then
    new.first_agent_response_at := timezone('utc', now());
  else
    new.first_agent_response_at := old.first_agent_response_at;
  end if;

  return new;
end;
$$;

create or replace function public.record_guest_booking_status_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.booking_status_history (
      booking_request_id,
      status,
      changed_by,
      reason
    )
    values (
      new.id,
      new.booking_status,
      auth.uid(),
      'Guest inquiry created'
    );
    return new;
  end if;

  if new.booking_status is distinct from old.booking_status then
    insert into public.booking_status_history (
      booking_request_id,
      status,
      changed_by,
      reason
    )
    values (
      new.id,
      new.booking_status,
      auth.uid(),
      'Guest inquiry status updated'
    );
  end if;

  return new;
end;
$$;

create or replace function public.create_guest_booking_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agent_profile_id uuid;
  v_listing_title text;
begin
  select a.profile_id, l.title
  into v_agent_profile_id, v_listing_title
  from public.agents a
  join public.listings l on l.id = new.listing_id
  where a.id = new.agent_id
  limit 1;

  if v_agent_profile_id is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    insert into public.notifications (
      user_id,
      booking_request_id,
      type,
      title,
      body,
      payload
    )
    values (
      v_agent_profile_id,
      new.id,
      'booking_created'::public.notification_type,
      'New inquiry received',
      coalesce(v_listing_title, 'Listing') || ' | ' || new.customer_name || ' | ' || new.customer_phone_number,
      jsonb_build_object(
        'bookingId', new.id,
        'listingId', new.listing_id,
        'requestReference', new.request_reference
      )
    );
    return new;
  end if;

  if new.booking_status is distinct from old.booking_status
     and public.is_admin(auth.uid()) then
    insert into public.notifications (
      user_id,
      booking_request_id,
      type,
      title,
      body,
      payload
    )
    values (
      v_agent_profile_id,
      new.id,
      'booking_status_changed'::public.notification_type,
      'Inquiry status updated',
      coalesce(v_listing_title, 'Listing') || ' | status ' || new.booking_status::text,
      jsonb_build_object(
        'bookingId', new.id,
        'listingId', new.listing_id,
        'requestReference', new.request_reference,
        'bookingStatus', new.booking_status::text
      )
    );
  end if;

  return new;
end;
$$;

create trigger prepare_guest_booking_request
before insert on public.booking_requests
for each row execute function public.prepare_guest_booking_request();

create trigger guard_guest_booking_request_update
before update on public.booking_requests
for each row execute function public.guard_guest_booking_request_update();

create trigger record_guest_booking_status_history
after insert or update of booking_status on public.booking_requests
for each row execute function public.record_guest_booking_status_history();

create trigger create_guest_booking_notification
after insert or update of booking_status on public.booking_requests
for each row execute function public.create_guest_booking_notification();

drop policy if exists "profiles_self_or_admin_select" on public.profiles;
create policy "profiles_self_or_admin_select"
on public.profiles
for select
using (auth.uid() = id or public.is_admin());

drop policy if exists "profiles_self_update" on public.profiles;
create policy "profiles_self_update"
on public.profiles
for update
using (auth.uid() = id)
with check (auth.uid() = id);

drop policy if exists "user_roles_self_or_admin_select" on public.user_roles;
create policy "user_roles_self_or_admin_select"
on public.user_roles
for select
using (auth.uid() = profile_id or public.is_admin());

drop policy if exists "user_roles_self_add_agent" on public.user_roles;
drop policy if exists "user_roles_admin_all" on public.user_roles;
create policy "user_roles_admin_all"
on public.user_roles
for all
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "agents_public_verified_or_owner_select" on public.agents;
drop policy if exists "agents_public_active_or_owner_select" on public.agents;
drop policy if exists "agents_self_or_admin_select" on public.agents;
drop policy if exists "agents_self_insert" on public.agents;
drop policy if exists "agents_self_update" on public.agents;
drop policy if exists "agents_self_safe_update" on public.agents;
drop policy if exists "agents_admin_update_all" on public.agents;
drop policy if exists "agents_admin_all" on public.agents;
create policy "agents_admin_all"
on public.agents
for all
using (public.is_admin())
with check (public.is_admin());

create policy "agents_self_safe_update"
on public.agents
for update
using (
  profile_id = auth.uid()
  and account_status = 'active'::public.agent_account_status
)
with check (
  profile_id = auth.uid()
  and account_status = 'active'::public.agent_account_status
);

drop policy if exists "agent_documents_agent_or_admin_all" on public.agent_documents;
drop policy if exists "agents_and_admins_manage_agent_documents" on public.agent_documents;
drop policy if exists "agent_documents_active_agent_or_admin_all" on public.agent_documents;
drop policy if exists "agent_documents_owner_or_admin_all" on public.agent_documents;
create policy "agent_documents_owner_or_admin_all"
on public.agent_documents
for all
using (
  public.is_admin()
  or (
    public.can_manage_agent_documents()
    and agent_id = public.current_agent_id()
  )
)
with check (
  public.is_admin()
  or (
    public.can_manage_agent_documents()
    and agent_id = public.current_agent_id()
  )
);

drop policy if exists "locations_active_select" on public.locations;
create policy "locations_active_select"
on public.locations
for select
using (is_active or public.is_admin());

drop policy if exists "locations_admin_all" on public.locations;
create policy "locations_admin_all"
on public.locations
for all
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "owners_agent_or_admin_all" on public.owners;
drop policy if exists "owners_owner_or_admin_select" on public.owners;
drop policy if exists "owners_owner_or_admin_insert" on public.owners;
drop policy if exists "owners_owner_or_admin_update" on public.owners;
drop policy if exists "owners_owner_or_admin_delete" on public.owners;

create policy "owners_owner_or_admin_select"
on public.owners
for select
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.agents
      where public.agents.id = owners.agent_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

create policy "owners_owner_or_admin_insert"
on public.owners
for insert
with check (
  public.is_admin()
  or (
    public.is_agent_active()
    and agent_id = public.current_agent_id()
  )
);

create policy "owners_owner_or_admin_update"
on public.owners
for update
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.agents
      where public.agents.id = owners.agent_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
)
with check (
  public.is_admin()
  or (
    public.is_agent_active()
    and agent_id = public.current_agent_id()
  )
);

create policy "owners_owner_or_admin_delete"
on public.owners
for delete
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.agents
      where public.agents.id = owners.agent_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

drop policy if exists "listings_public_select_approved" on public.listings;
drop policy if exists "listings_agent_or_admin_all" on public.listings;
drop policy if exists "listings_owner_or_admin_select" on public.listings;
drop policy if exists "listings_owner_or_admin_insert" on public.listings;
drop policy if exists "listings_owner_or_admin_update" on public.listings;

create policy "listings_owner_or_admin_select"
on public.listings
for select
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.agents
      where public.agents.id = listings.agent_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

create policy "listings_owner_or_admin_insert"
on public.listings
for insert
with check (
  public.is_admin()
  or (
    public.is_agent_active()
    and agent_id = public.current_agent_id()
  )
);

create policy "listings_owner_or_admin_update"
on public.listings
for update
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.agents
      where public.agents.id = listings.agent_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
)
with check (
  public.is_admin()
  or (
    public.is_agent_active()
    and agent_id = public.current_agent_id()
  )
);

drop policy if exists "listing_media_follow_listing_visibility_select" on public.listing_media;
drop policy if exists "listing_media_agent_or_admin_all" on public.listing_media;
drop policy if exists "listing_media_owner_or_admin_select" on public.listing_media;
drop policy if exists "listing_media_owner_or_admin_insert" on public.listing_media;
drop policy if exists "listing_media_owner_or_admin_update" on public.listing_media;
drop policy if exists "listing_media_owner_or_admin_delete" on public.listing_media;

create policy "listing_media_owner_or_admin_select"
on public.listing_media
for select
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = listing_media.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

create policy "listing_media_owner_or_admin_insert"
on public.listing_media
for insert
with check (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = listing_media.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

create policy "listing_media_owner_or_admin_update"
on public.listing_media
for update
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = listing_media.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
)
with check (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = listing_media.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

create policy "listing_media_owner_or_admin_delete"
on public.listing_media
for delete
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = listing_media.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

drop policy if exists "property_details_follow_listing_visibility" on public.property_details;
drop policy if exists "property_details_agent_or_admin_all" on public.property_details;
drop policy if exists "property_details_owner_or_admin_select" on public.property_details;
drop policy if exists "property_details_owner_or_admin_write" on public.property_details;

create policy "property_details_owner_or_admin_select"
on public.property_details
for select
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = property_details.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

create policy "property_details_owner_or_admin_write"
on public.property_details
for all
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = property_details.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
)
with check (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = property_details.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

drop policy if exists "vehicle_details_follow_listing_visibility" on public.vehicle_details;
drop policy if exists "vehicle_details_agent_or_admin_all" on public.vehicle_details;
drop policy if exists "vehicle_details_owner_or_admin_select" on public.vehicle_details;
drop policy if exists "vehicle_details_owner_or_admin_write" on public.vehicle_details;

create policy "vehicle_details_owner_or_admin_select"
on public.vehicle_details
for select
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = vehicle_details.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

create policy "vehicle_details_owner_or_admin_write"
on public.vehicle_details
for all
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = vehicle_details.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
)
with check (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = vehicle_details.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

drop policy if exists "venue_details_follow_listing_visibility" on public.venue_details;
drop policy if exists "venue_details_agent_or_admin_all" on public.venue_details;
drop policy if exists "venue_details_owner_or_admin_select" on public.venue_details;
drop policy if exists "venue_details_owner_or_admin_write" on public.venue_details;

create policy "venue_details_owner_or_admin_select"
on public.venue_details
for select
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = venue_details.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

create policy "venue_details_owner_or_admin_write"
on public.venue_details
for all
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = venue_details.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
)
with check (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = venue_details.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

drop policy if exists "farm_details_follow_listing_visibility" on public.farm_details;
drop policy if exists "farm_details_owner_or_admin_select" on public.farm_details;
drop policy if exists "farm_details_owner_or_admin_write" on public.farm_details;

create policy "farm_details_owner_or_admin_select"
on public.farm_details
for select
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = farm_details.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

create policy "farm_details_owner_or_admin_write"
on public.farm_details
for all
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = farm_details.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
)
with check (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = farm_details.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

drop policy if exists "listing_private_locations_agent_or_admin_all" on public.listing_private_locations;
drop policy if exists "listing_private_locations_owner_or_admin_select" on public.listing_private_locations;
drop policy if exists "listing_private_locations_owner_or_admin_write" on public.listing_private_locations;

create policy "listing_private_locations_owner_or_admin_select"
on public.listing_private_locations
for select
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = listing_private_locations.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

create policy "listing_private_locations_owner_or_admin_write"
on public.listing_private_locations
for all
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = listing_private_locations.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
)
with check (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = listing_private_locations.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

drop policy if exists "availability_blocks_agent_or_admin_all" on public.availability_blocks;
drop policy if exists "availability_blocks_owner_or_admin_select" on public.availability_blocks;
drop policy if exists "availability_blocks_owner_or_admin_write" on public.availability_blocks;

create policy "availability_blocks_owner_or_admin_select"
on public.availability_blocks
for select
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = availability_blocks.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

create policy "availability_blocks_owner_or_admin_write"
on public.availability_blocks
for all
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = availability_blocks.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
)
with check (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.listings
      join public.agents on public.agents.id = public.listings.agent_id
      where public.listings.id = availability_blocks.listing_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

drop policy if exists "booking_requests_customer_agent_admin_select" on public.booking_requests;
drop policy if exists "booking_requests_customer_insert" on public.booking_requests;
drop policy if exists "booking_requests_customer_agent_admin_update" on public.booking_requests;
drop policy if exists "booking_requests_agent_admin_select" on public.booking_requests;
drop policy if exists "booking_requests_agent_admin_update" on public.booking_requests;

create policy "booking_requests_active_agent_admin_select"
on public.booking_requests
for select
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.agents
      where public.agents.id = booking_requests.agent_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

create policy "booking_requests_active_agent_admin_update"
on public.booking_requests
for update
using (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.agents
      where public.agents.id = booking_requests.agent_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
)
with check (
  public.is_admin()
  or (
    public.is_agent_active()
    and exists (
      select 1
      from public.agents
      where public.agents.id = booking_requests.agent_id
        and public.agents.profile_id = auth.uid()
        and public.agents.account_status = 'active'::public.agent_account_status
    )
  )
);

drop policy if exists "booking_history_visible_to_booking_participants" on public.booking_status_history;
drop policy if exists "booking_history_visible_to_agent_or_admin" on public.booking_status_history;

create policy "booking_history_visible_to_active_agent_or_admin"
on public.booking_status_history
for select
using (
  exists (
    select 1
    from public.booking_requests
    where public.booking_requests.id = booking_status_history.booking_request_id
      and (
        public.is_admin()
        or (
          public.is_agent_active()
          and exists (
            select 1
            from public.agents
            where public.agents.id = public.booking_requests.agent_id
              and public.agents.profile_id = auth.uid()
              and public.agents.account_status = 'active'::public.agent_account_status
          )
        )
      )
  )
);

drop policy if exists "device_tokens_self_all" on public.device_tokens;
create policy "device_tokens_manage_session_all"
on public.device_tokens
for all
using (
  public.is_admin()
  or (
    user_id = auth.uid()
    and public.can_access_manage_session()
  )
)
with check (
  public.is_admin()
  or (
    user_id = auth.uid()
    and public.can_access_manage_session()
  )
);

drop policy if exists "notifications_self_select" on public.notifications;
drop policy if exists "notifications_self_update" on public.notifications;

create policy "notifications_manage_session_select"
on public.notifications
for select
using (
  public.is_admin()
  or (
    user_id = auth.uid()
    and public.can_access_manage_session()
  )
);

create policy "notifications_manage_session_update"
on public.notifications
for update
using (
  public.is_admin()
  or (
    user_id = auth.uid()
    and public.can_access_manage_session()
  )
)
with check (
  public.is_admin()
  or (
    user_id = auth.uid()
    and public.can_access_manage_session()
  )
);

create or replace function public.guard_listing_workflow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agent public.agents%rowtype;
  v_owner_agent_id uuid;
  v_category public.asset_categories%rowtype;
  v_allowed_reason text[] := array['agent_removed', 'rented'];
  v_admin_allowed_reason text[] := array['admin_removed', 'suspended', 'rented'];
begin
  if new.category_id is null and new.category is not null then
    new.category_id := public.listing_category_id_from_legacy(new.category);
  end if;

  if new.category_id is null then
    raise exception 'category_id is required for listings';
  end if;

  select *
  into v_category
  from public.asset_categories
  where id = new.category_id;

  if v_category.id is null then
    raise exception 'Selected category_id does not exist';
  end if;

  if not public.is_valid_listing_location(new.location_id) then
    raise exception 'Listings must use Region -> District -> Area, with optional Ward and Street';
  end if;

  if new.owner_id is not null then
    select agent_id
    into v_owner_agent_id
    from public.owners
    where id = new.owner_id;
  end if;

  new.category := public.listing_category_from_category_id(new.category_id);
  new.listing_attributes := public.sanitize_listing_attributes(
    new.category_id,
    coalesce(new.listing_attributes, '{}'::jsonb)
  );
  new.public_location_label := public.build_public_location_label(new.location_id);
  new.approval_status := 'approved'::public.approval_status;

  if public.is_admin(auth.uid()) then
    if new.removed_reason is not null
      and not (new.removed_reason = any (v_admin_allowed_reason))
    then
      raise exception 'Admin removal reason must be admin_removed, suspended, or rented';
    end if;

    if tg_op = 'INSERT' then
      new.published_at := coalesce(new.published_at, timezone('utc', now()));
    elsif new.status = 'active'::public.listing_status then
      new.published_at := coalesce(new.published_at, old.published_at, timezone('utc', now()));
    end if;

    if new.removed_reason is not null then
      new.status := 'inactive'::public.listing_status;
      new.removed_from_market_at := coalesce(new.removed_from_market_at, timezone('utc', now()));
      if new.removed_reason = 'rented' then
        new.availability_status := 'rented'::public.availability_status;
      end if;
    elsif new.status = 'active'::public.listing_status then
      new.removed_from_market_at := null;
      new.removed_reason := null;
      if new.availability_status = 'rented'::public.availability_status then
        new.availability_status := 'available'::public.availability_status;
      end if;
    end if;

    return new;
  end if;

  select *
  into v_agent
  from public.agents
  where profile_id = auth.uid();

  if v_agent.id is null then
    raise exception 'Only provisioned agents can manage listings';
  end if;

  if v_agent.account_status <> 'active'::public.agent_account_status then
    raise exception 'Only active agents can manage listings';
  end if;

  if not v_category.is_active then
    raise exception 'Active agents can use only active categories';
  end if;

  if new.owner_id is not null and v_owner_agent_id is distinct from v_agent.id then
    raise exception 'Agents can attach only their own owner records';
  end if;

  if new.removed_reason is not null
    and not (new.removed_reason = any (v_allowed_reason))
  then
    raise exception 'Agent removal reason must be agent_removed or rented';
  end if;

  if tg_op = 'INSERT' then
    new.agent_id := v_agent.id;
    if new.removed_reason is not null then
      new.status := 'inactive'::public.listing_status;
      new.removed_from_market_at := coalesce(new.removed_from_market_at, timezone('utc', now()));
      if new.removed_reason = 'rented' then
        new.availability_status := 'rented'::public.availability_status;
      end if;
    else
      new.status := 'active'::public.listing_status;
      new.removed_from_market_at := null;
      new.removed_reason := null;
      new.published_at := coalesce(new.published_at, timezone('utc', now()));
    end if;
    return new;
  end if;

  if old.agent_id <> v_agent.id then
    raise exception 'Agents can edit only their own listings';
  end if;

  new.agent_id := old.agent_id;

  if new.status in ('suspended'::public.listing_status, 'expired'::public.listing_status) then
    raise exception 'Only admin can suspend or expire listings';
  end if;

  if new.removed_reason is not null then
    new.status := 'inactive'::public.listing_status;
    new.removed_from_market_at := coalesce(
      new.removed_from_market_at,
      old.removed_from_market_at,
      timezone('utc', now())
    );
    if new.removed_reason = 'rented' then
      new.availability_status := 'rented'::public.availability_status;
    end if;
  elsif new.status = 'active'::public.listing_status then
    new.removed_from_market_at := null;
    new.removed_reason := null;
    if new.availability_status = 'rented'::public.availability_status then
      new.availability_status := 'available'::public.availability_status;
    end if;
    new.published_at := coalesce(old.published_at, timezone('utc', now()));
  else
    new.published_at := old.published_at;
  end if;

  return new;
end;
$$;

drop trigger if exists guard_listing_workflow on public.listings;
create trigger guard_listing_workflow
before insert or update on public.listings
for each row execute function public.guard_listing_workflow();

create or replace function public.get_public_listing_detail(p_listing_id uuid)
returns table (
  listing_id uuid,
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
  media jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    l.id as listing_id,
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
  where l.id = p_listing_id
    and public.is_listing_public(l.id);
$$;

create or replace function public.get_public_home_feed(
  p_limit integer default 20,
  p_page integer default 0,
  p_selected_region_id uuid default null,
  p_selected_district_id uuid default null,
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
      case
        when p_latitude is not null
         and p_longitude is not null
         and loc.latitude is not null
         and loc.longitude is not null
        then power(loc.latitude - p_latitude, 2) + power(loc.longitude - p_longitude, 2)
        else null
      end as gps_distance_score,
      case
        when p_selected_district_id is not null
         and public.location_ancestor_id(l.location_id, 'district'::public.location_type) = p_selected_district_id then 1
        when p_selected_region_id is not null
         and public.location_ancestor_id(l.location_id, 'region'::public.location_type) = p_selected_region_id then 2
        when p_latitude is not null and p_longitude is not null then 3
        else 4
      end as priority_group,
      (
        (('x' || substr(
          md5(coalesce(p_session_seed, to_char(current_date, 'YYYYMMDD')) || ':' || l.id::text),
          1,
          8
        ))::bit(32)::bigint)::numeric + 1
      ) / 4294967296::numeric as random_unit
    from public.listings l
    join public.asset_categories c on c.id = l.category_id
    left join public.locations loc on loc.id = l.location_id
    left join public.listing_media lm
      on lm.listing_id = l.id
     and lm.is_cover = true
    where public.is_listing_public(l.id)
  ),
  ranked_houses as (
    select
      e.*,
      row_number() over (
        order by
          e.priority_group asc,
          e.gps_distance_score nulls last,
          e.random_unit asc,
          e.listing_id
      ) as item_rank
    from eligible e
    where e.category_slug = 'house'
  ),
  ranked_others as (
    select
      e.*,
      row_number() over (
        order by
          e.priority_group asc,
          e.gps_distance_score nulls last,
          (-ln(greatest(e.random_unit, 0.000001::numeric))) / greatest(e.home_feed_weight, 1) asc,
          e.random_unit asc,
          e.listing_id
      ) as item_rank
    from eligible e
    where e.category_slug <> 'house'
  ),
  mixed_feed as (
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
      district_id,
      (item_rank * 2) - 1 as feed_position
    from ranked_houses
    union all
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
      district_id,
      item_rank * 2 as feed_position
    from ranked_others
  ),
  ordered_feed as (
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
      district_id,
      row_number() over (order by feed_position asc, listing_id) as absolute_position
    from mixed_feed
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
  from ordered_feed
  order by absolute_position asc
  offset greatest(coalesce(p_page, 0), 0) * greatest(least(coalesce(p_limit, 20), 50), 1)
  limit greatest(least(coalesce(p_limit, 20), 50), 1);
$$;

create or replace function public.get_public_listings(
  p_category_slug text default null,
  p_search_text text default null,
  p_region_id uuid default null,
  p_district_id uuid default null,
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
      case
        when p_latitude is not null
         and p_longitude is not null
         and loc.latitude is not null
         and loc.longitude is not null
        then power(loc.latitude - p_latitude, 2) + power(loc.longitude - p_longitude, 2)
        else null
      end as gps_distance_score,
      case
        when p_district_id is not null
         and public.location_ancestor_id(l.location_id, 'district'::public.location_type) = p_district_id then 1
        when p_region_id is not null
         and public.location_ancestor_id(l.location_id, 'region'::public.location_type) = p_region_id then 2
        when p_latitude is not null and p_longitude is not null then 3
        else 4
      end as priority_group,
      (
        (('x' || substr(
          md5(coalesce(p_session_seed, to_char(current_date, 'YYYYMMDD')) || ':' || l.id::text),
          1,
          8
        ))::bit(32)::bigint)::numeric + 1
      ) / 4294967296::numeric as random_unit
    from public.listings l
    join public.asset_categories c on c.id = l.category_id
    left join public.locations loc on loc.id = l.location_id
    left join public.listing_media lm
      on lm.listing_id = l.id
     and lm.is_cover = true
    where public.is_listing_public(l.id)
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
    priority_group asc,
    gps_distance_score nulls last,
    case
      when p_search_text is null or btrim(p_search_text) = '' then 1
      when title ilike btrim(p_search_text) || '%' then 0
      else 1
    end,
    (-ln(greatest(random_unit, 0.000001::numeric))) / greatest(home_feed_weight, 1) asc,
    random_unit asc,
    listing_id
  offset greatest(coalesce(p_page, 0), 0) * greatest(least(coalesce(p_limit, 20), 50), 1)
  limit greatest(least(coalesce(p_limit, 20), 50), 1);
$$;

create table if not exists public.platform_promotions (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  description text,
  cta_label text,
  target_url text,
  placement text not null check (
    placement in (
      'global',
      'home_feed',
      'category_page',
      'listing_detail',
      'manage_dashboard',
      'website'
    )
  ),
  visibility_scope text not null default 'all' check (
    visibility_scope in ('public', 'manage', 'admin', 'all')
  ),
  start_at timestamptz,
  end_at timestamptz,
  display_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.platform_promotion_media (
  id uuid primary key default gen_random_uuid(),
  promotion_id uuid not null references public.platform_promotions (id) on delete cascade,
  media_type public.media_type not null,
  media_path text not null,
  thumbnail_path text,
  display_order integer not null default 0,
  is_primary boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

drop trigger if exists set_platform_promotions_updated_at on public.platform_promotions;
create trigger set_platform_promotions_updated_at
before update on public.platform_promotions
for each row execute procedure public.set_updated_at();

drop trigger if exists set_platform_promotion_media_updated_at on public.platform_promotion_media;
create trigger set_platform_promotion_media_updated_at
before update on public.platform_promotion_media
for each row execute procedure public.set_updated_at();

create unique index if not exists idx_platform_promotion_primary_media
  on public.platform_promotion_media (promotion_id)
  where is_primary = true;

create index if not exists idx_platform_promotions_active_window
  on public.platform_promotions (placement, visibility_scope, is_active, display_order, start_at, end_at);

alter table public.platform_promotions enable row level security;
alter table public.platform_promotion_media enable row level security;

drop policy if exists "platform_promotions_admin_all" on public.platform_promotions;
create policy "platform_promotions_admin_all"
on public.platform_promotions
for all
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "platform_promotion_media_admin_all" on public.platform_promotion_media;
create policy "platform_promotion_media_admin_all"
on public.platform_promotion_media
for all
using (public.is_admin())
with check (public.is_admin());

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'agent-documents',
  'agent-documents',
  false,
  10485760,
  array['application/pdf', 'image/png', 'image/jpeg']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "agent_documents_owner_select_object" on storage.objects;
create policy "agent_documents_owner_select_object"
on storage.objects
for select
using (
  bucket_id = 'agent-documents'
  and (
    public.is_admin()
    or (
      public.can_manage_agent_documents()
      and (
        name like auth.uid()::text || '/%'
        or name like 'agent-documents/' || auth.uid()::text || '/%'
      )
    )
  )
);

drop policy if exists "agent_documents_owner_insert_object" on storage.objects;
create policy "agent_documents_owner_insert_object"
on storage.objects
for insert
with check (
  bucket_id = 'agent-documents'
  and (
    public.is_admin()
    or (
      public.can_manage_agent_documents()
      and (
        name like auth.uid()::text || '/%'
        or name like 'agent-documents/' || auth.uid()::text || '/%'
      )
    )
  )
);

drop policy if exists "agent_documents_owner_update_object" on storage.objects;
create policy "agent_documents_owner_update_object"
on storage.objects
for update
using (
  bucket_id = 'agent-documents'
  and (
    public.is_admin()
    or (
      public.can_manage_agent_documents()
      and (
        name like auth.uid()::text || '/%'
        or name like 'agent-documents/' || auth.uid()::text || '/%'
      )
    )
  )
)
with check (
  bucket_id = 'agent-documents'
  and (
    public.is_admin()
    or (
      public.can_manage_agent_documents()
      and (
        name like auth.uid()::text || '/%'
        or name like 'agent-documents/' || auth.uid()::text || '/%'
      )
    )
  )
);

drop policy if exists "agent_documents_owner_delete_object" on storage.objects;
create policy "agent_documents_owner_delete_object"
on storage.objects
for delete
using (
  bucket_id = 'agent-documents'
  and (
    public.is_admin()
    or (
      public.can_manage_agent_documents()
      and (
        name like auth.uid()::text || '/%'
        or name like 'agent-documents/' || auth.uid()::text || '/%'
      )
    )
  )
);

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'listing-media',
  'listing-media',
  false,
  26214400,
  array['image/jpeg', 'image/png', 'image/webp', 'video/mp4']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "agents_manage_own_listing_media_files" on storage.objects;
drop policy if exists "listing_media_public_listing_read_object" on storage.objects;
create policy "listing_media_public_listing_read_object"
on storage.objects
for select
using (
  bucket_id = 'listing-media'
  and public.is_public_listing_media_object(name)
);

drop policy if exists "listing_media_agent_active_select_object" on storage.objects;
create policy "listing_media_agent_active_select_object"
on storage.objects
for select
using (
  bucket_id = 'listing-media'
  and (
    public.is_admin()
    or (
      public.is_agent_active()
      and (
        name like auth.uid()::text || '/%'
        or name like 'listing-media/' || auth.uid()::text || '/%'
      )
    )
  )
);

drop policy if exists "listing_media_agent_active_insert" on storage.objects;
create policy "listing_media_agent_active_insert"
on storage.objects
for insert
with check (
  bucket_id = 'listing-media'
  and public.is_agent_active()
  and (
    name like auth.uid()::text || '/%'
    or name like 'listing-media/' || auth.uid()::text || '/%'
  )
);

drop policy if exists "listing_media_agent_active_update" on storage.objects;
create policy "listing_media_agent_active_update"
on storage.objects
for update
using (
  bucket_id = 'listing-media'
  and public.is_agent_active()
  and (
    name like auth.uid()::text || '/%'
    or name like 'listing-media/' || auth.uid()::text || '/%'
  )
)
with check (
  bucket_id = 'listing-media'
  and public.is_agent_active()
  and (
    name like auth.uid()::text || '/%'
    or name like 'listing-media/' || auth.uid()::text || '/%'
  )
);

drop policy if exists "listing_media_agent_active_delete" on storage.objects;
create policy "listing_media_agent_active_delete"
on storage.objects
for delete
using (
  bucket_id = 'listing-media'
  and public.is_agent_active()
  and (
    name like auth.uid()::text || '/%'
    or name like 'listing-media/' || auth.uid()::text || '/%'
  )
);

drop policy if exists "listing_media_admin_manage" on storage.objects;
create policy "listing_media_admin_manage"
on storage.objects
for all
using (
  bucket_id = 'listing-media'
  and public.is_admin()
)
with check (
  bucket_id = 'listing-media'
  and public.is_admin()
);

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'platform-promotions',
  'platform-promotions',
  false,
  26214400,
  array['image/jpeg', 'image/png', 'image/webp', 'video/mp4']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "platform_promotions_viewer_read" on storage.objects;
create policy "platform_promotions_viewer_read"
on storage.objects
for select
using (
  bucket_id = 'platform-promotions'
  and public.can_access_promotion_media_object(name)
);

drop policy if exists "platform_promotions_admin_write" on storage.objects;
create policy "platform_promotions_admin_write"
on storage.objects
for all
using (
  bucket_id = 'platform-promotions'
  and public.is_admin()
)
with check (
  bucket_id = 'platform-promotions'
  and public.is_admin()
);

create or replace function public.get_active_platform_promotions(
  p_surface text,
  p_placement text default 'global',
  p_limit integer default 4
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
      public.is_agent_active(auth.uid()) as is_active_agent
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
  cross join viewer v
  left join lateral (
    select media_type, media_path, thumbnail_path
    from public.platform_promotion_media
    where promotion_id = p.id
    order by is_primary desc, display_order asc, created_at asc
    limit 1
  ) pm on true
  where p.is_active = true
    and coalesce(p.start_at, timezone('utc', now())) <= timezone('utc', now())
    and coalesce(p.end_at, timezone('utc', now()) + interval '100 years') >= timezone('utc', now())
    and (p.placement = p_placement or p.placement = 'global')
    and (
      v.is_admin
      or (
        v.is_active_agent
        and p_placement in ('global', 'manage_dashboard')
        and p.placement in ('global', 'manage_dashboard')
      )
      or (
        not v.is_admin
        and not v.is_active_agent
        and p_placement in ('global', 'home_feed', 'category_page', 'listing_detail', 'website')
        and p.placement in ('global', 'home_feed', 'category_page', 'listing_detail', 'website')
      )
    )
    and (
      (not v.is_admin and not v.is_active_agent and p.visibility_scope in ('public', 'all'))
      or (v.is_active_agent and p.visibility_scope in ('public', 'manage', 'all'))
      or (v.is_admin and p.visibility_scope in ('public', 'manage', 'admin', 'all'))
    )
  order by
    case when p.placement = 'global' then 0 else 1 end,
    p.display_order asc,
    p.created_at desc
  limit greatest(coalesce(p_limit, 4), 1);
$$;

revoke all on function public.current_agent_id() from public, anon, authenticated;
grant execute on function public.current_agent_id() to authenticated, service_role;

revoke all on function public.current_agent_context() from public, anon, authenticated;
grant execute on function public.current_agent_context() to authenticated, service_role;

revoke all on function public.get_my_agent_status() from public, anon, authenticated;
grant execute on function public.get_my_agent_status() to authenticated, service_role;

revoke all on function public.submit_agent_application(text, text, text) from public, anon, authenticated;
grant execute on function public.submit_agent_application(text, text, text) to authenticated, service_role;

revoke all on function public.update_my_agent_profile(text, text) from public, anon, authenticated;
grant execute on function public.update_my_agent_profile(text, text) to authenticated, service_role;

revoke all on function public.is_agent_active(uuid) from public, anon, authenticated;
grant execute on function public.is_agent_active(uuid) to authenticated, service_role;

revoke all on function public.can_manage_agent_documents(uuid) from public, anon, authenticated;
grant execute on function public.can_manage_agent_documents(uuid) to authenticated, service_role;

revoke all on function public.can_access_manage_session(uuid) from public, anon, authenticated;
grant execute on function public.can_access_manage_session(uuid) to authenticated, service_role;

revoke all on function public.sanitize_listing_attributes(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.sanitize_listing_attributes(uuid, jsonb) to authenticated, service_role;

revoke all on function public.is_listing_public(uuid) from public, anon, authenticated;
grant execute on function public.is_listing_public(uuid) to anon, authenticated, service_role;

revoke all on function public.is_public_listing_media_object(text) from public, anon, authenticated;
grant execute on function public.is_public_listing_media_object(text) to anon, authenticated, service_role;

revoke all on function public.viewer_can_access_promotion(text, text) from public, anon, authenticated;
grant execute on function public.viewer_can_access_promotion(text, text) to anon, authenticated, service_role;

revoke all on function public.can_access_promotion_media_object(text) from public, anon, authenticated;
grant execute on function public.can_access_promotion_media_object(text) to anon, authenticated, service_role;

revoke all on function public.get_listing_inquiry_counts(uuid[]) from public, anon, authenticated;
grant execute on function public.get_listing_inquiry_counts(uuid[]) to authenticated, service_role;

revoke all on function public.get_public_home_feed(integer, integer, uuid, uuid, double precision, double precision, text) from public, anon, authenticated;
grant execute on function public.get_public_home_feed(integer, integer, uuid, uuid, double precision, double precision, text) to anon, authenticated, service_role;

revoke all on function public.get_public_listings(text, text, uuid, uuid, integer, integer, double precision, double precision, text) from public, anon, authenticated;
grant execute on function public.get_public_listings(text, text, uuid, uuid, integer, integer, double precision, double precision, text) to anon, authenticated, service_role;

revoke all on function public.get_public_listing_detail(uuid) from public, anon, authenticated;
grant execute on function public.get_public_listing_detail(uuid) to anon, authenticated, service_role;

revoke all on function public.get_active_platform_promotions(text, text, integer) from public, anon, authenticated;
grant execute on function public.get_active_platform_promotions(text, text, integer) to anon, authenticated, service_role;

do $$
begin
  if exists (
    select 1
    from pg_trigger
    where tgname = 'guard_listing_workflow'
      and tgrelid = 'public.listings'::regclass
  ) then
    alter table public.listings enable trigger guard_listing_workflow;
  end if;
end
$$;

commit;
