-- Admin-managed listing fields live in asset_categories.field_schema. Listing
-- values remain in listings.listing_attributes, so adding a field never
-- requires a new database column or application release.

create or replace function public.validate_listing_field_schema(p_schema jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  v_field jsonb;
  v_key text;
  v_label text;
  v_type text;
  v_options jsonb;
  v_result jsonb := '[]'::jsonb;
  v_seen_keys text[] := array[]::text[];
  v_private_keys text[] := array[
    'exact_address', 'address', 'phone', 'phone_number', 'owner',
    'owner_name', 'agent', 'agent_phone', 'latitude', 'longitude',
    'map_pin_latitude', 'map_pin_longitude', 'gps'
  ];
begin
  if p_schema is null or jsonb_typeof(p_schema) <> 'array' then
    raise exception 'field_schema must be an array of listing fields';
  end if;

  if jsonb_array_length(p_schema) > 100 then
    raise exception 'A category cannot contain more than 100 listing fields';
  end if;

  for v_field in select value from jsonb_array_elements(p_schema)
  loop
    if jsonb_typeof(v_field) <> 'object' then
      raise exception 'Every listing field must be an object';
    end if;

    v_key := lower(btrim(coalesce(v_field ->> 'key', '')));
    v_label := btrim(coalesce(v_field ->> 'label', ''));
    v_type := lower(btrim(coalesce(v_field ->> 'type', 'text')));

    if v_key !~ '^[a-z][a-z0-9_]{0,62}$' then
      raise exception 'Invalid listing field key "%"', v_key;
    end if;
    if v_key = any (v_private_keys) then
      raise exception 'Private listing field key "%" is not allowed', v_key;
    end if;
    if v_key = any (v_seen_keys) then
      raise exception 'Duplicate listing field key "%"', v_key;
    end if;
    if v_label = '' or char_length(v_label) > 100 then
      raise exception 'Listing field "%" must have a label of 1-100 characters', v_key;
    end if;
    if v_type not in ('text', 'textarea', 'number', 'boolean', 'select') then
      raise exception 'Unsupported listing field type "%" for key "%"', v_type, v_key;
    end if;

    v_options := coalesce(v_field -> 'options', '[]'::jsonb);
    if v_type = 'select' then
      if jsonb_typeof(v_options) <> 'array' or jsonb_array_length(v_options) = 0 then
        raise exception 'Select field "%" must have at least one option', v_key;
      end if;
      if exists (
        select 1
        from jsonb_array_elements(v_options) option_value
        where jsonb_typeof(option_value) <> 'string'
           or btrim(option_value #>> '{}') = ''
      ) then
        raise exception 'Select field "%" options must be non-empty text', v_key;
      end if;
      if (
        select count(*) <> count(distinct option_value #>> '{}')
        from jsonb_array_elements(v_options) option_value
      ) then
        raise exception 'Select field "%" contains duplicate options', v_key;
      end if;
    end if;

    v_seen_keys := array_append(v_seen_keys, v_key);
    v_result := v_result || jsonb_build_array(
      jsonb_strip_nulls(jsonb_build_object(
        'key', v_key,
        'label', v_label,
        'type', v_type,
        'required', coalesce((v_field ->> 'required')::boolean, false),
        'active', coalesce((v_field ->> 'active')::boolean, true),
        'help_text', nullif(btrim(v_field ->> 'help_text'), ''),
        'options', case when v_type = 'select' then v_options else null end
      ))
    );
  end loop;

  return v_result;
exception
  when invalid_text_representation then
    raise exception 'Listing field required and active values must be boolean';
end;
$$;

create or replace function public.guard_listing_field_schema()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_field jsonb;
  v_key text;
  v_new_field jsonb;
begin
  new.field_schema := public.validate_listing_field_schema(new.field_schema);

  if tg_op = 'UPDATE' and new.field_schema is distinct from old.field_schema then
    -- A key/type is part of persisted JSON data. It may be relabelled, have its
    -- options extended, or be retired with active=false, but never silently
    -- removed or retyped while listings still contain that key.
    for v_old_field in select value from jsonb_array_elements(old.field_schema)
    loop
      v_key := v_old_field ->> 'key';
      if exists (
        select 1 from public.listings
        where category_id = old.id and listing_attributes ? v_key
      ) then
        select value into v_new_field
        from jsonb_array_elements(new.field_schema)
        where value ->> 'key' = v_key
        limit 1;
        if v_new_field is null then
          raise exception 'Field "%" contains listing data and must be retired instead of removed', v_key;
        end if;
        if coalesce(v_new_field ->> 'type', 'text') <>
           coalesce(v_old_field ->> 'type', 'text') then
          raise exception 'Field "%" contains listing data and its type cannot be changed', v_key;
        end if;
        if coalesce(v_old_field ->> 'type', 'text') = 'select' and exists (
          select 1
          from public.listings l
          where l.category_id = old.id
            and l.listing_attributes ? v_key
            and not exists (
              select 1
              from jsonb_array_elements_text(
                coalesce(v_new_field -> 'options', '[]'::jsonb)
              ) option_value
              where option_value = l.listing_attributes ->> v_key
            )
        ) then
          raise exception 'Field "%" options still contain values used by listings', v_key;
        end if;
      end if;
    end loop;
  end if;
  return new;
end;
$$;

-- Normalize the currently seeded schemas before installing the write guard.
update public.asset_categories
set field_schema = public.validate_listing_field_schema(field_schema);

drop trigger if exists guard_listing_field_schema on public.asset_categories;
create trigger guard_listing_field_schema
before insert or update of field_schema on public.asset_categories
for each row execute function public.guard_listing_field_schema();

revoke all on function public.validate_listing_field_schema(jsonb) from public;
grant execute on function public.validate_listing_field_schema(jsonb)
  to authenticated, service_role;

comment on column public.asset_categories.field_schema is
  'Admin-managed definitions for dynamic listings.listing_attributes fields.';
