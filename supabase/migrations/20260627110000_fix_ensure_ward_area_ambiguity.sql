create or replace function public.ensure_ward_area(
  p_ward_id uuid,
  p_area_name text
)
returns table (
  id uuid,
  parent_id uuid,
  location_type public.location_type,
  name text,
  created_new boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ward public.locations%rowtype;
  v_existing public.locations%rowtype;
  v_created public.locations%rowtype;
  v_area_name text;
  v_area_count integer;
begin
  v_area_name := public.normalize_location_name(p_area_name);
  if p_ward_id is null then
    raise exception 'Ward is required before choosing or creating an area';
  end if;
  if v_area_name is null then
    raise exception 'Area name is required';
  end if;

  select *
  into v_ward
  from public.locations as l
  where l.id = p_ward_id
    and l.location_type = 'ward'::public.location_type
    and l.is_active = true;

  if v_ward.id is null then
    raise exception 'Ward was not found or is inactive';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_ward_id::text));

  select *
  into v_existing
  from public.locations as l
  where l.parent_id = p_ward_id
    and l.location_type = 'area'::public.location_type
    and lower(l.name) = lower(v_area_name)
  limit 1;

  if v_existing.id is not null then
    return query
    select
      v_existing.id,
      v_existing.parent_id,
      v_existing.location_type,
      v_existing.name,
      false;
    return;
  end if;

  select count(*)
  into v_area_count
  from public.locations as l
  where l.parent_id = p_ward_id
    and l.location_type = 'area'::public.location_type;

  if v_area_count >= 100 then
    raise exception 'This ward already has 100 saved areas. Choose one of the existing saved areas.';
  end if;

  begin
    insert into public.locations (
      parent_id,
      location_type,
      name,
      is_active
    )
    values (
      p_ward_id,
      'area'::public.location_type,
      v_area_name,
      true
    )
    returning * into v_created;
  exception
    when unique_violation then
      select *
      into v_existing
      from public.locations as l
      where l.parent_id = p_ward_id
        and l.location_type = 'area'::public.location_type
        and lower(l.name) = lower(v_area_name)
      limit 1;

      if v_existing.id is null then
        raise;
      end if;

      return query
      select
        v_existing.id,
        v_existing.parent_id,
        v_existing.location_type,
        v_existing.name,
        false;
      return;
  end;

  return query
  select
    v_created.id,
    v_created.parent_id,
    v_created.location_type,
    v_created.name,
    true;
end;
$$;

grant execute on function public.ensure_ward_area(uuid, text) to anon, authenticated, service_role;
