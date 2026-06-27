alter table public.agents
  add column if not exists display_name text,
  add column if not exists phone_number text,
  add column if not exists contact_email text,
  add column if not exists nida_number text,
  add column if not exists location_id uuid references public.locations (id) on delete set null,
  add column if not exists public_location_label text,
  add column if not exists profile_photo_path text,
  add column if not exists profile_photo_updated_at timestamptz;

update public.agents a
set
  display_name = coalesce(
    nullif(btrim(a.display_name), ''),
    nullif(btrim(p.full_name), ''),
    nullif(btrim(a.business_name), ''),
    'Agent'
  ),
  phone_number = coalesce(
    nullif(btrim(a.phone_number), ''),
    nullif(btrim(p.phone_number), '')
  ),
  public_location_label = public.build_public_location_label(a.location_id)
from public.profiles p
where p.id = a.profile_id;

create or replace function public.set_agent_public_location_label()
returns trigger
language plpgsql
as $$
begin
  new.public_location_label := public.build_public_location_label(new.location_id);
  return new;
end;
$$;

drop trigger if exists set_agent_public_location_label on public.agents;
create trigger set_agent_public_location_label
before insert or update of location_id on public.agents
for each row execute function public.set_agent_public_location_label();

create or replace function public.guard_agent_account_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.display_name := coalesce(
      nullif(btrim(new.display_name), ''),
      nullif(btrim(new.business_name), ''),
      'Agent'
    );
    new.phone_number := nullif(btrim(new.phone_number), '');
    new.contact_email := nullif(lower(btrim(new.contact_email)), '');
    new.nida_number := nullif(upper(btrim(new.nida_number)), '');
    new.profile_photo_path := nullif(btrim(new.profile_photo_path), '');

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

  new.display_name := coalesce(
    nullif(btrim(new.display_name), ''),
    nullif(btrim(old.display_name), ''),
    nullif(btrim(old.business_name), ''),
    'Agent'
  );
  new.phone_number := nullif(btrim(new.phone_number), '');
  new.contact_email := nullif(lower(btrim(new.contact_email)), '');
  new.nida_number := nullif(upper(btrim(new.nida_number)), '');
  new.profile_photo_path := nullif(btrim(new.profile_photo_path), '');

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
    or new.nida_number is distinct from old.nida_number
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
  new.nida_number := old.nida_number;

  return new;
end;
$$;

create or replace function public.get_my_agent_status()
returns table (
  id uuid,
  profile_id uuid,
  display_name text,
  phone_number text,
  contact_email text,
  nida_number text,
  location_id uuid,
  public_location_label text,
  profile_photo_path text,
  business_name text,
  business_description text,
  account_status text,
  verification_status text,
  verified_at timestamptz,
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
    a.display_name,
    a.phone_number,
    a.contact_email,
    a.nida_number,
    a.location_id,
    a.public_location_label,
    a.profile_photo_path,
    a.business_name,
    a.business_description,
    a.account_status::text,
    a.verification_status::text,
    a.verified_at,
    a.activated_at,
    a.deactivated_at,
    a.deactivation_reason
  from public.agents a
  where a.profile_id = auth.uid()
  limit 1;
$$;

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
    coalesce(nullif(btrim(a.display_name), ''), nullif(btrim(a.business_name), ''), 'Agent') as agent_display_name,
    a.business_name as agent_business_name,
    a.phone_number as agent_phone_number,
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
  district_id uuid,
  agent_id uuid,
  agent_display_name text,
  agent_business_name text,
  agent_phone_number text,
  agent_location_label text,
  agent_verification_status text,
  agent_verified_at timestamptz,
  agent_profile_photo_path text
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
      a.id as agent_id,
      coalesce(nullif(btrim(a.display_name), ''), nullif(btrim(a.business_name), ''), 'Agent') as agent_display_name,
      a.business_name as agent_business_name,
      a.phone_number as agent_phone_number,
      a.public_location_label as agent_location_label,
      a.verification_status::text as agent_verification_status,
      a.verified_at as agent_verified_at,
      a.profile_photo_path as agent_profile_photo_path,
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
    join public.agents a on a.id = l.agent_id
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
      agent_id,
      agent_display_name,
      agent_business_name,
      agent_phone_number,
      agent_location_label,
      agent_verification_status,
      agent_verified_at,
      agent_profile_photo_path,
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
      agent_id,
      agent_display_name,
      agent_business_name,
      agent_phone_number,
      agent_location_label,
      agent_verification_status,
      agent_verified_at,
      agent_profile_photo_path,
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
      agent_id,
      agent_display_name,
      agent_business_name,
      agent_phone_number,
      agent_location_label,
      agent_verification_status,
      agent_verified_at,
      agent_profile_photo_path,
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
    district_id,
    agent_id,
    agent_display_name,
    agent_business_name,
    agent_phone_number,
    agent_location_label,
    agent_verification_status,
    agent_verified_at,
    agent_profile_photo_path
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
  district_id uuid,
  agent_id uuid,
  agent_display_name text,
  agent_business_name text,
  agent_phone_number text,
  agent_location_label text,
  agent_verification_status text,
  agent_verified_at timestamptz,
  agent_profile_photo_path text
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
      a.id as agent_id,
      coalesce(nullif(btrim(a.display_name), ''), nullif(btrim(a.business_name), ''), 'Agent') as agent_display_name,
      a.business_name as agent_business_name,
      a.phone_number as agent_phone_number,
      a.public_location_label as agent_location_label,
      a.verification_status::text as agent_verification_status,
      a.verified_at as agent_verified_at,
      a.profile_photo_path as agent_profile_photo_path,
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
    join public.agents a on a.id = l.agent_id
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
        or a.display_name ilike '%' || btrim(p_search_text) || '%'
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
    district_id,
    agent_id,
    agent_display_name,
    agent_business_name,
    agent_phone_number,
    agent_location_label,
    agent_verification_status,
    agent_verified_at,
    agent_profile_photo_path
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

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'agent-profile-photos',
  'agent-profile-photos',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "agent_profile_photos_agent_active_insert" on storage.objects;
create policy "agent_profile_photos_agent_active_insert"
on storage.objects
for insert
with check (
  bucket_id = 'agent-profile-photos'
  and (
    public.is_admin()
    or (
      public.is_agent_active()
      and (
        name like auth.uid()::text || '/%'
        or name like 'agent-profile-photos/' || auth.uid()::text || '/%'
      )
    )
  )
);

drop policy if exists "agent_profile_photos_agent_active_update" on storage.objects;
create policy "agent_profile_photos_agent_active_update"
on storage.objects
for update
using (
  bucket_id = 'agent-profile-photos'
  and (
    public.is_admin()
    or (
      public.is_agent_active()
      and (
        name like auth.uid()::text || '/%'
        or name like 'agent-profile-photos/' || auth.uid()::text || '/%'
      )
    )
  )
)
with check (
  bucket_id = 'agent-profile-photos'
  and (
    public.is_admin()
    or (
      public.is_agent_active()
      and (
        name like auth.uid()::text || '/%'
        or name like 'agent-profile-photos/' || auth.uid()::text || '/%'
      )
    )
  )
);

drop policy if exists "agent_profile_photos_agent_active_delete" on storage.objects;
create policy "agent_profile_photos_agent_active_delete"
on storage.objects
for delete
using (
  bucket_id = 'agent-profile-photos'
  and (
    public.is_admin()
    or (
      public.is_agent_active()
      and (
        name like auth.uid()::text || '/%'
        or name like 'agent-profile-photos/' || auth.uid()::text || '/%'
      )
    )
  )
);
