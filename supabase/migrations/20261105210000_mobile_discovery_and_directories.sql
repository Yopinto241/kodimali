-- Read-only directory projections preserve the underlying table RLS.
create or replace view public.manage_listing_directory with (security_invoker = true) as
select l.*,
 public.location_ancestor_id(l.location_id, 'region'::public.location_type) as directory_region_id,
 public.location_ancestor_id(l.location_id, 'district'::public.location_type) as directory_district_id,
 public.location_ancestor_id(l.location_id, 'ward'::public.location_type) as directory_ward_id,
 public.location_ancestor_id(l.location_id, 'area'::public.location_type) as directory_area_id
from public.listings l;
revoke all on public.manage_listing_directory from public, anon, authenticated;
grant select on public.manage_listing_directory to authenticated, service_role;

create or replace function public.search_admin_agents_by_location(
  p_location_id uuid default null,
  p_search_text text default null,
  p_account_status text default null,
  p_verification_status text default null,
  p_limit integer default 40,
  p_offset integer default 0
)
returns table (
  agent_id uuid,
  profile_id uuid,
  display_name text,
  phone_number text,
  contact_email text,
  nida_number text,
  public_location_label text,
  profile_photo_path text,
  verified_at timestamptz,
  business_name text,
  business_description text,
  verification_status text,
  account_status text,
  activated_at timestamptz,
  deactivated_at timestamptz,
  deactivation_reason text,
  created_at timestamptz,
  profile_full_name text,
  profile_username text,
  profile_account_email text,
  profile_account_email_confirmed_at timestamptz,
  profile_preferred_language text,
  profile_phone_number text,
  profile_avatar_url text,
  agent_documents jsonb,
  agent_service_categories jsonb,
  total_count bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  with filters as (
    select
      nullif(btrim(coalesce(p_search_text, '')), '') as search_text,
      nullif(btrim(coalesce(p_account_status, '')), '') as account_status,
      nullif(
        btrim(coalesce(p_verification_status, '')),
        ''
      ) as verification_status,
      greatest(coalesce(p_limit, 40), 1) as page_limit,
      greatest(coalesce(p_offset, 0), 0) as page_offset
  ),
  filtered as (
    select
      a.id as agent_id,
      a.profile_id,
      a.display_name,
      a.phone_number,
      a.contact_email,
      a.nida_number,
      a.public_location_label,
      a.profile_photo_path,
      a.verified_at,
      a.business_name,
      a.business_description,
      a.verification_status::text as verification_status,
      a.account_status::text as account_status,
      a.activated_at,
      a.deactivated_at,
      a.deactivation_reason,
      a.created_at,
      p.full_name as profile_full_name,
      p.username as profile_username,
      p.account_email as profile_account_email,
      p.account_email_confirmed_at as profile_account_email_confirmed_at,
      p.preferred_language as profile_preferred_language,
      p.phone_number as profile_phone_number,
      p.avatar_url as profile_avatar_url,
      count(*) over() as total_count
    from public.agents a
    join public.profiles p
      on p.id = a.profile_id
    cross join filters f
    where (p_location_id is null or a.location_id = p_location_id
      or public.location_ancestor_id(a.location_id, 'region'::public.location_type) = p_location_id
      or public.location_ancestor_id(a.location_id, 'district'::public.location_type) = p_location_id
      or public.location_ancestor_id(a.location_id, 'ward'::public.location_type) = p_location_id
      or public.location_ancestor_id(a.location_id, 'area'::public.location_type) = p_location_id)
    and (
      f.account_status is null
      or a.account_status = f.account_status::public.agent_account_status
    )
      and (
        f.verification_status is null
        or a.verification_status =
          f.verification_status::public.agent_verification_status
      )
      and (
        f.search_text is null
        or coalesce(a.display_name, '') ilike '%' || f.search_text || '%'
        or coalesce(a.business_name, '') ilike '%' || f.search_text || '%'
        or coalesce(a.business_description, '') ilike '%' || f.search_text || '%'
        or coalesce(a.phone_number, '') ilike '%' || f.search_text || '%'
        or coalesce(a.contact_email, '') ilike '%' || f.search_text || '%'
        or coalesce(a.nida_number, '') ilike '%' || f.search_text || '%'
        or coalesce(a.public_location_label, '') ilike '%' || f.search_text || '%'
        or coalesce(p.full_name, '') ilike '%' || f.search_text || '%'
        or coalesce(p.username, '') ilike '%' || f.search_text || '%'
        or coalesce(p.account_email, '') ilike '%' || f.search_text || '%'
        or coalesce(p.phone_number, '') ilike '%' || f.search_text || '%'
      )
    order by a.created_at desc, a.id desc
    limit (select page_limit from filters)
    offset (select page_offset from filters)
  )
  select
    f.agent_id,
    f.profile_id,
    f.display_name,
    f.phone_number,
    f.contact_email,
    f.nida_number,
    f.public_location_label,
    f.profile_photo_path,
    f.verified_at,
    f.business_name,
    f.business_description,
    f.verification_status,
    f.account_status,
    f.activated_at,
    f.deactivated_at,
    f.deactivation_reason,
    f.created_at,
    f.profile_full_name,
    f.profile_username,
    f.profile_account_email,
    f.profile_account_email_confirmed_at,
    f.profile_preferred_language,
    f.profile_phone_number,
    f.profile_avatar_url,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', d.id,
            'document_type', d.document_type,
            'storage_path', d.storage_path
          )
          order by d.document_type, d.id
        )
        from public.agent_documents d
        where d.agent_id = f.agent_id
      ),
      '[]'::jsonb
    ) as agent_documents,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'category_id', acs.category_id,
            'is_primary', acs.is_primary,
            'asset_categories', jsonb_build_object(
              'id', c.id,
              'name', c.name,
              'slug', c.slug,
              'icon_key', c.icon_key
            )
          )
          order by acs.is_primary desc, c.name, c.id
        )
        from public.agent_service_categories acs
        join public.asset_categories c
          on c.id = acs.category_id
        where acs.agent_id = f.agent_id
      ),
      '[]'::jsonb
    ) as agent_service_categories,
    f.total_count
  from filtered f;
$$;


revoke all on function public.search_admin_agents_by_location(uuid,text,text,text,integer,integer) from public, anon;
grant execute on function public.search_admin_agents_by_location(uuid,text,text,text,integer,integer) to authenticated, service_role;

-- Equivalent Swahili and English terms; every query token must match.
create or replace function public.marketplace_keyword_variants(p_word text)
returns text[] language sql immutable set search_path = public as $$
 select case
 when p_word = any(array['nyumba','house','houses','home','homes']) then array['nyumba','house','houses','home','homes']
 when p_word = any(array['chumba','vyumba','room','rooms','bedroom','bedrooms']) then array['chumba','vyumba','room','rooms','bedroom','bedrooms']
 when p_word = any(array['kiwanja','viwanja','plot','plots','land']) then array['kiwanja','viwanja','plot','plots','land']
 when p_word = any(array['shamba','mashamba','farm','farms']) then array['shamba','mashamba','farm','farms']
 when p_word = any(array['gari','magari','car','cars','vehicle','vehicles']) then array['gari','magari','car','cars','vehicle','vehicles']
 when p_word = any(array['fleti','apartment','apartments','flat','flats']) then array['fleti','apartment','apartments','flat','flats']
 when p_word = any(array['ofisi','office','offices']) then array['ofisi','office','offices']
 when p_word = any(array['duka','maduka','shop','shops']) then array['duka','maduka','shop','shops']
 when p_word = any(array['ghala','maghala','warehouse','warehouses']) then array['ghala','maghala','warehouse','warehouses']
 when p_word = any(array['ukumbi','kumbi','hall','halls','venue','venues']) then array['ukumbi','kumbi','hall','halls','venue','venues']
 when p_word = any(array['kukodisha','kupanga','kodi','rent','rental','rentals']) then array['kukodisha','kupanga','kodi','rent','rental','rentals']
 else array[p_word] end
$$;
create or replace function public.marketplace_matches_search(p_content text, p_query text)
returns boolean language sql immutable set search_path = public as $$
 select not exists (
  select 1 from regexp_split_to_table(lower(trim(left(coalesce(p_query,''),256))), '[^[:alnum:]]+') word
  where word <> '' and word <> all(array['a','an','the','in','at','for','to','na','ya','wa','za','la','kwa','cha','vya','ni','nataka','nahitaji','tafuta','looking'])
   and not exists (select 1 from unnest(public.marketplace_keyword_variants(word)) variant
     where lower(regexp_replace(coalesce(p_content,''),'[_-]',' ','g')) ~ ('\m' || variant || '\M'))
 )
$$;

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
      and public.marketplace_matches_search(concat_ws(' ', l.title,l.description,l.public_location_label,c.name,c.slug,l.listing_attributes::text),p_search_text)
  ), counted as (select eligible.*, count(*) over () total_count from eligible)
  select listing_id, title, public_location_label, price_amount, price_period, availability_status,
    category_id, category_name, category_slug, category_icon_key, home_feed_weight, cover_storage_path,
    region_id, district_id, published_at, total_count
  from counted
  order by
    case when coalesce(p_sort, 'recommended') = 'price_low' then price_amount end asc nulls last,
    case when coalesce(p_sort, 'recommended') = 'price_high' then price_amount end desc nulls last,
    case when coalesce(p_sort, 'recommended') = 'newest' then published_at end desc nulls last,
    case when p_search_text is null or btrim(p_search_text) = '' then 0 when title ilike btrim(p_search_text) || '%' then 0 else 1 end,
    case when coalesce(p_sort, 'recommended') = 'recommended' and nullif(trim(p_search_text),'') is null then random_unit end asc nulls last,
    published_at desc, listing_id
  offset greatest(coalesce(p_page, 0), 0) * greatest(least(coalesce(p_limit, 40), 100), 1)
  limit greatest(least(coalesce(p_limit, 40), 100), 1);
$$;

revoke all on function public.search_public_listings_v2(text, text, uuid, uuid, uuid, uuid, numeric, numeric, text, text, integer, integer, double precision, double precision, text) from public;
grant execute on function public.search_public_listings_v2(text, text, uuid, uuid, uuid, uuid, numeric, numeric, text, text, integer, integer, double precision, double precision, text) to anon, authenticated, service_role;

notify pgrst, 'reload schema';

-- Public suggestions contain location names only, never listing contact data.
create or replace function public.suggest_marketplace_locations(p_query text)
returns table(location_id uuid,name text,location_type text,label text)
language sql stable security invoker set search_path = public as $$
 select l.id,l.name,l.location_type::text,concat_ws(', ',l.name,p.name)
 from public.locations l left join public.locations p on p.id=l.parent_id
 where l.is_active and l.location_type::text in ('region','district','ward','area')
 and length(trim(coalesce(p_query,''))) >= 2
 and position(lower(trim(p_query)) in lower(l.name)) > 0
 order by case when lower(l.name)=lower(trim(p_query)) then 0
   when starts_with(lower(l.name),lower(trim(p_query))) then 1 else 2 end,
   case l.location_type::text when 'region' then 0 when 'district' then 1 when 'ward' then 2 else 3 end,l.name,l.id
 limit 8
$$;
revoke all on function public.suggest_marketplace_locations(text) from public;
grant execute on function public.suggest_marketplace_locations(text) to anon,authenticated,service_role;
notify pgrst,'reload schema';

-- Staff locations are independent of agent ownership and role permissions.
create table if not exists public.admin_work_locations (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 location_id uuid not null references public.locations(id) on delete restrict,
 assigned_by uuid references public.profiles(id), updated_at timestamptz not null default now()
);
alter table public.admin_work_locations enable row level security;
revoke all on public.admin_work_locations from public,anon,authenticated;
grant select on public.admin_work_locations to authenticated;
grant all on public.admin_work_locations to service_role;
drop policy if exists admin_work_locations_super_admin_read on public.admin_work_locations;
create policy admin_work_locations_super_admin_read on public.admin_work_locations
 for select to authenticated using (public.is_super_admin());
create or replace function public.set_admin_work_location(p_user_id uuid,p_location_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_super_admin() then raise exception 'Super Admin required';end if;
 if not exists(select 1 from public.admin_role_assignments where user_id=p_user_id)
   and not exists(select 1 from public.user_roles where profile_id=p_user_id and role='admin')
 then raise exception 'Assign an administrative role before setting a staff location';end if;
 if p_location_id is null then delete from public.admin_work_locations where user_id=p_user_id;return;end if;
 if not exists(select 1 from public.locations where id=p_location_id and is_active
   and location_type::text in ('region','district','ward','area','street'))
 then raise exception 'Choose an active region, district, ward or area';end if;
 insert into public.admin_work_locations(user_id,location_id,assigned_by) values(p_user_id,p_location_id,auth.uid())
 on conflict(user_id) do update set location_id=excluded.location_id,assigned_by=excluded.assigned_by,updated_at=now();
end $$;
revoke all on function public.set_admin_work_location(uuid,uuid) from public,anon;
grant execute on function public.set_admin_work_location(uuid,uuid) to authenticated,service_role;

-- Only Super Admin may see the staff/role directory. Never infer missing locations.
create or replace function public.get_admin_role_directory_by_location(p_location_id uuid default null)
returns table(user_id uuid,full_name text,account_email text,roles jsonb,location_id uuid,location_label text)
language sql stable security definer set search_path=public as $$
 select p.id,p.full_name,p.account_email,
   coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name) order by r.rank desc)
    from public.admin_role_assignments ra join public.admin_role_definitions r on r.id=ra.role_id where ra.user_id=p.id),'[]'::jsonb),
   coalesce(w.location_id,t.location_id,a.location_id),coalesce(l.name,'Unassigned location')
 from public.profiles p
 left join public.admin_work_locations w on w.user_id=p.id
 left join public.agents a on a.profile_id=p.id
 left join public.supervisor_territories t on t.supervisor_id=p.id
 left join public.locations l on l.id=coalesce(w.location_id,t.location_id,a.location_id)
 where public.is_super_admin() and (p_location_id is null or l.id=p_location_id
   or public.location_ancestor_id(l.id,'region'::public.location_type)=p_location_id
   or public.location_ancestor_id(l.id,'district'::public.location_type)=p_location_id
   or public.location_ancestor_id(l.id,'ward'::public.location_type)=p_location_id
   or public.location_ancestor_id(l.id,'area'::public.location_type)=p_location_id)
 order by coalesce(l.name,'~'),p.full_name,p.id limit 1000
$$;
revoke all on function public.get_admin_role_directory_by_location(uuid) from public,anon;
grant execute on function public.get_admin_role_directory_by_location(uuid) to authenticated,service_role;
notify pgrst,'reload schema';

-- Keep successful devices across retry attempts; do not resend to them when
-- another installation is temporarily offline.
alter table public.notification_delivery_outbox
 add column if not exists delivered_device_ids uuid[] not null default '{}';
