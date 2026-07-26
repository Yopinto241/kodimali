create or replace function public.normalize_location_name(raw_name text)
returns text
language sql
immutable
as $$
  select nullif(regexp_replace(btrim(coalesce(raw_name, '')), '\s+', ' ', 'g'), '');
$$;

create or replace function public.validate_location_hierarchy()
returns trigger
language plpgsql
as $$
declare
  v_parent public.locations%rowtype;
  v_area_count integer;
begin
  new.name := public.normalize_location_name(new.name);
  if new.name is null then
    raise exception 'Location name is required';
  end if;

  if new.location_type = 'country'::public.location_type then
    if new.parent_id is not null then
      raise exception 'Country cannot have a parent location';
    end if;
    return new;
  end if;

  if new.parent_id is null then
    raise exception '% requires a parent location', new.location_type::text;
  end if;

  select *
  into v_parent
  from public.locations
  where id = new.parent_id;

  if v_parent.id is null then
    raise exception 'Parent location was not found';
  end if;

  case new.location_type
    when 'region'::public.location_type then
      if v_parent.location_type <> 'country'::public.location_type then
        raise exception 'Region must belong to a country';
      end if;
    when 'district'::public.location_type then
      if v_parent.location_type <> 'region'::public.location_type then
        raise exception 'District must belong to a region';
      end if;
    when 'ward'::public.location_type then
      if v_parent.location_type <> 'district'::public.location_type then
        raise exception 'Ward must belong to a district';
      end if;
    when 'area'::public.location_type then
      if v_parent.location_type <> 'ward'::public.location_type then
        raise exception 'Area must belong to a ward';
      end if;

      select count(*)
      into v_area_count
      from public.locations
      where parent_id = new.parent_id
        and location_type = 'area'::public.location_type
        and id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid);

      if v_area_count >= 100 then
        raise exception 'This ward already has 100 saved areas. Choose one of the existing saved areas.';
      end if;
    when 'street'::public.location_type then
      if v_parent.location_type <> 'area'::public.location_type then
        raise exception 'Street must belong to an area';
      end if;
    else
      raise exception 'Unsupported location type %', new.location_type::text;
  end case;

  return new;
end;
$$;

drop trigger if exists validate_location_hierarchy on public.locations;
create trigger validate_location_hierarchy
before insert or update of parent_id, location_type, name
on public.locations
for each row execute function public.validate_location_hierarchy();

do $$
declare
  v_district record;
  v_ward_id uuid;
  v_ward_name text;
  v_name_suffix integer;
  v_batch_index integer;
  v_batch_total integer;
  v_area_ids uuid[];
begin
  for v_district in
    select distinct d.id, d.name
    from public.locations d
    join public.locations a
      on a.parent_id = d.id
     and a.location_type = 'area'::public.location_type
    where d.location_type = 'district'::public.location_type
  loop
    select coalesce(array_agg(a.id order by lower(a.name), a.id), '{}'::uuid[])
    into v_area_ids
    from public.locations a
    where a.parent_id = v_district.id
      and a.location_type = 'area'::public.location_type;

    if coalesce(array_length(v_area_ids, 1), 0) = 0 then
      continue;
    end if;

    v_batch_total := ceil(array_length(v_area_ids, 1)::numeric / 100.0);

    for v_batch_index in 1..v_batch_total loop
      if v_batch_index = 1 then
        v_ward_name := 'Imported Areas Ward';
      else
        v_ward_name := format('Imported Areas Ward %s', v_batch_index);
      end if;
      v_name_suffix := v_batch_index;

      while exists (
        select 1
        from public.locations w
        where w.parent_id = v_district.id
          and w.location_type = 'ward'::public.location_type
          and lower(w.name) = lower(v_ward_name)
      ) loop
        v_name_suffix := v_name_suffix + 1;
        v_ward_name := format('Imported Areas Ward %s', v_name_suffix);
      end loop;

      insert into public.locations (
        parent_id,
        location_type,
        name,
        is_active
      )
      values (
        v_district.id,
        'ward'::public.location_type,
        v_ward_name,
        true
      )
      returning id into v_ward_id;

      update public.locations
      set parent_id = v_ward_id
      where id = any (
        v_area_ids[
          ((v_batch_index - 1) * 100 + 1):least(v_batch_index * 100, array_length(v_area_ids, 1))
        ]
      );
    end loop;
  end loop;
end
$$;

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

create or replace function public.is_valid_agent_location(check_location_id uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.locations l
    where l.id = check_location_id
      and l.is_active = true
      and l.location_type = 'area'::public.location_type
      and public.location_ancestor_id(l.id, 'ward'::public.location_type) is not null
      and public.location_ancestor_id(l.id, 'district'::public.location_type) is not null
      and public.location_ancestor_id(l.id, 'region'::public.location_type) is not null
  );
$$;

create or replace function public.guard_agent_location_hierarchy()
returns trigger
language plpgsql
as $$
begin
  if new.location_id is null then
    raise exception 'Agent location is required';
  end if;

  if not public.is_valid_agent_location(new.location_id) then
    raise exception 'Agent location must be an active area linked to ward, district, and region';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_agent_location_hierarchy on public.agents;
create trigger guard_agent_location_hierarchy
before insert or update of location_id
on public.agents
for each row execute function public.guard_agent_location_hierarchy();

create or replace function public.is_valid_listing_location(check_location_id uuid)
returns boolean
language plpgsql
stable
as $$
declare
  v_location public.locations%rowtype;
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

  if v_location.location_type not in (
    'ward'::public.location_type,
    'area'::public.location_type,
    'street'::public.location_type
  ) then
    return false;
  end if;

  return public.location_ancestor_id(check_location_id, 'region'::public.location_type) is not null
    and public.location_ancestor_id(check_location_id, 'district'::public.location_type) is not null;
end;
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

update public.agents
set public_location_label = public.build_public_location_label(location_id)
where location_id is not null;

update public.listings
set public_location_label = public.build_public_location_label(location_id)
where location_id is not null;

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
