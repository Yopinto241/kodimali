-- Existing production hierarchy validator, copied for isolated tests.
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
