-- Event catalog filters use the same region -> district -> ward -> area tree
-- as rentals. A provider covering a parent location also covers its children.
create or replace function public.location_is_within(
  check_location_id uuid,
  selected_location_id uuid
)
returns boolean
language sql
stable
set search_path = public
as $$
  with recursive chain as (
    select id, parent_id from public.locations where id = check_location_id
    union all
    select parent.id, parent.parent_id
    from chain join public.locations parent on parent.id = chain.parent_id
  )
  select selected_location_id is null
    or exists(select 1 from chain where id = selected_location_id);
$$;

create or replace function public.search_public_event_equipment(
  p_search text default null, p_category_id uuid default null,
  p_location_id uuid default null, p_start_at timestamptz default null,
  p_end_at timestamptz default null, p_min_price numeric default null,
  p_max_price numeric default null, p_sort text default 'recommended',
  p_limit integer default 20, p_offset integer default 0
)
returns table(id uuid,name text,description text,category_id uuid,category_name_sw text,category_name_en text,public_location_label text,price_amount_tzs numeric,price_unit text,total_quantity integer,available_quantity integer,media_paths jsonb,setup_minutes integer,return_buffer_minutes integer,security_deposit_tzs numeric)
language sql stable security definer set search_path=public as $$
 select e.id,e.name,e.description,e.category_id,c.name_sw,c.name_en,e.public_location_label,e.price_amount_tzs,e.price_unit,e.total_quantity,
 greatest(0,e.total_quantity-coalesce((select sum(a.quantity)::integer from public.event_equipment_allocations a where a.equipment_id=e.id and a.status in('held','confirmed') and(p_start_at is null or p_end_at is null or a.occupied_period&&tstzrange(p_start_at-make_interval(mins=>e.setup_minutes),p_end_at+make_interval(mins=>e.return_buffer_minutes),'[)'))and(a.expires_at is null or a.expires_at>now())),0))::integer,e.media_paths,e.setup_minutes,e.return_buffer_minutes,e.security_deposit_tzs
 from public.event_equipment_items e join public.event_equipment_categories c on c.id=e.category_id
 where e.verification_status='verified' and e.publication_status='published' and e.is_active
 and(p_category_id is null or e.category_id=p_category_id)
 and(p_location_id is null or public.location_is_within(e.location_id,p_location_id))
 and(p_min_price is null or e.price_amount_tzs>=p_min_price)and(p_max_price is null or e.price_amount_tzs<=p_max_price)
 and(nullif(trim(p_search),'') is null or to_tsvector('simple',coalesce(e.name,'')||' '||coalesce(e.description,''))@@plainto_tsquery('simple',trim(p_search)))
 order by case when p_sort='price_low' then e.price_amount_tzs end asc,case when p_sort='price_high' then e.price_amount_tzs end desc,case when p_sort='newest' then e.created_at end desc,e.created_at desc
 limit least(greatest(p_limit,1),50) offset greatest(p_offset,0)
$$;

create or replace function public.search_public_event_services(
  p_search text default null,p_provider_kind text default null,
  p_location_id uuid default null,p_start_at timestamptz default null,
  p_end_at timestamptz default null,p_min_price numeric default null,
  p_max_price numeric default null,p_sort text default 'recommended',
  p_limit integer default 20,p_offset integer default 0
)
returns table(offering_id uuid,provider_id uuid,title text,description text,display_name text,provider_kind text,biography text,experience_years integer,pricing_mode text,price_amount_tzs numeric,duration_minutes integer,portfolio_media jsonb,is_available boolean)
language sql stable security definer set search_path=public as $$
 select o.id,p.id,o.title,o.description,p.display_name,p.provider_kind,p.biography,p.experience_years,o.pricing_mode,o.price_amount_tzs,o.duration_minutes,p.portfolio_media,
 not exists(select 1 from public.event_provider_unavailability u where u.provider_id=p.id and p_start_at is not null and p_end_at is not null and u.unavailable_period&&tstzrange(p_start_at,p_end_at,'[)'))
 and not exists(select 1 from public.event_service_bookings b where b.provider_id=p.id and b.status in('held','confirmed')and p_start_at is not null and p_end_at is not null and b.service_period&&tstzrange(p_start_at,p_end_at,'[)')and(b.expires_at is null or b.expires_at>now()))
 from public.event_service_offerings o join public.event_service_profiles p on p.id=o.provider_id
 where o.is_active and o.publication_status='published' and p.is_active and p.verification_status='verified'
 and(p_provider_kind is null or p.provider_kind=p_provider_kind)
 and(p_min_price is null or o.price_amount_tzs is null or o.price_amount_tzs>=p_min_price)
 and(p_max_price is null or o.price_amount_tzs is null or o.price_amount_tzs<=p_max_price)
 and(p_location_id is null or exists(select 1 from public.event_service_areas a where a.profile_id=p.id and(public.location_is_within(a.location_id,p_location_id) or public.location_is_within(p_location_id,a.location_id))))
 and(nullif(trim(p_search),'') is null or to_tsvector('simple',coalesce(o.title,'')||' '||coalesce(o.description,'')||' '||coalesce(p.display_name,''))@@plainto_tsquery('simple',trim(p_search)))
 order by case when p_sort='price_low' then o.price_amount_tzs end asc nulls last,case when p_sort='price_high' then o.price_amount_tzs end desc nulls last,case when p_sort='newest' then o.created_at end desc,o.created_at desc
 limit least(greatest(p_limit,1),50) offset greatest(p_offset,0)
$$;

revoke all on function public.location_is_within(uuid,uuid) from public;
grant execute on function public.location_is_within(uuid,uuid) to anon,authenticated,service_role;
