-- Production registration/location definitions used by the isolated fixture.
create or replace function public.normalize_manage_username(value text)
returns text
language sql
immutable
as $$
  select nullif(
    regexp_replace(lower(coalesce(btrim(value), '')), '[^a-z0-9_]+', '_', 'g'),
    ''
  );
$$;
create or replace function public.normalize_manage_phone(value text)
returns text
language sql
immutable
as $$
  select nullif(regexp_replace(coalesce(value, ''), '[^0-9]+', '', 'g'), '');
$$;
create or replace function public.build_manage_username_candidate(
  requested_username text,
  full_name text,
  account_email text,
  phone_number text,
  profile_id uuid
)
returns text
language plpgsql
immutable
as $$
declare
  v_requested text := public.normalize_manage_username(requested_username);
  v_email_base text := public.normalize_manage_username(
    split_part(coalesce(account_email, ''), '@', 1)
  );
  v_name_base text := public.normalize_manage_username(full_name);
  v_phone_base text := public.normalize_manage_phone(phone_number);
  v_suffix text := substring(replace(profile_id::text, '-', '') from 1 for 6);
  v_base text;
begin
  if v_requested is not null and length(v_requested) between 3 and 32 then
    return v_requested;
  end if;

  v_base := coalesce(
    nullif(v_email_base, ''),
    nullif(v_name_base, ''),
    case
      when v_phone_base is not null then 'user_' || right(v_phone_base, 8)
      else null
    end,
    'user'
  );

  v_base := left(v_base, 24);

  if length(v_base) < 3 then
    v_base := 'user';
  end if;

  return left(v_base || '_' || v_suffix, 32);
end;
$$;
create or replace function public.handle_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_full_name text := coalesce(
    nullif(btrim(v_metadata ->> 'full_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'KODIMALI User'
  );
  v_phone_number text := nullif(btrim(v_metadata ->> 'phone_number'), '');
  v_preferred_language text := coalesce(
    nullif(btrim(v_metadata ->> 'preferred_language'), ''),
    'sw'
  );
  v_username text := public.build_manage_username_candidate(
    v_metadata ->> 'username',
    v_full_name,
    new.email,
    v_phone_number,
    new.id
  );
  v_register_as_agent boolean := coalesce(
    nullif(v_metadata ->> 'register_as_agent', '')::boolean,
    false
  );
  v_location_id uuid := nullif(btrim(v_metadata ->> 'location_id'), '')::uuid;
  v_nida_number text := nullif(upper(btrim(v_metadata ->> 'nida_number')), '');
  v_business_name text := coalesce(
    nullif(btrim(v_metadata ->> 'business_name'), ''),
    v_full_name
  );
  v_business_description text := nullif(
    btrim(v_metadata ->> 'business_description'),
    ''
  );
  v_primary_category_id uuid := nullif(
    btrim(v_metadata ->> 'primary_category_id'),
    ''
  )::uuid;
  v_agent_id uuid;
begin
  insert into public.profiles (
    id,
    full_name,
    phone_number,
    preferred_language,
    username,
    account_email,
    account_email_confirmed_at
  )
  values (
    new.id,
    v_full_name,
    v_phone_number,
    v_preferred_language,
    v_username,
    nullif(lower(btrim(new.email)), ''),
    new.email_confirmed_at
  )
  on conflict (id) do update
  set
    full_name = excluded.full_name,
    phone_number = coalesce(excluded.phone_number, public.profiles.phone_number),
    preferred_language = excluded.preferred_language,
    username = coalesce(public.profiles.username, excluded.username),
    account_email = excluded.account_email,
    account_email_confirmed_at = excluded.account_email_confirmed_at,
    updated_at = timezone('utc', now());

  if not v_register_as_agent then
    return new;
  end if;

  insert into public.user_roles (profile_id, role)
  values (new.id, 'agent'::public.app_role)
  on conflict (profile_id, role) do nothing;

  insert into public.agents (
    profile_id,
    display_name,
    phone_number,
    nida_number,
    location_id,
    business_name,
    business_description
  )
  values (
    new.id,
    v_full_name,
    v_phone_number,
    v_nida_number,
    v_location_id,
    v_business_name,
    v_business_description
  )
  on conflict (profile_id) do nothing
  returning id into v_agent_id;

  if v_agent_id is null then
    select id
    into v_agent_id
    from public.agents
    where profile_id = new.id
    limit 1;
  end if;

  if v_agent_id is not null and v_primary_category_id is not null then
    insert into public.agent_service_categories (
      agent_id,
      category_id,
      is_primary
    )
    values (
      v_agent_id,
      v_primary_category_id,
      true
    )
    on conflict (agent_id, category_id) do update
    set is_primary = excluded.is_primary;
  end if;

  return new;
end;
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
