-- Registrations made before handle_auth_user_created was installed can have an
-- auth user/profile but no agent workspace record. Reconcile those users from
-- the metadata submitted by the Manage app.
do $$
declare
  v_user record;
  v_agent_id uuid;
  v_location_id uuid;
  v_category_id uuid;
begin
  for v_user in
    select
      u.id,
      u.email,
      u.email_confirmed_at,
      coalesce(u.raw_user_meta_data, '{}'::jsonb) as metadata
    from auth.users u
    where coalesce(
      nullif(u.raw_user_meta_data ->> 'register_as_agent', '')::boolean,
      false
    )
      and u.raw_user_meta_data ->> 'registration_source' = 'agent_self_register'
      and not exists (
        select 1 from public.agents a where a.profile_id = u.id
      )
  loop
    v_location_id := case
      when coalesce(v_user.metadata ->> 'location_id', '')
        ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then (v_user.metadata ->> 'location_id')::uuid
      else null
    end;
    v_category_id := case
      when coalesce(v_user.metadata ->> 'primary_category_id', '')
        ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then (v_user.metadata ->> 'primary_category_id')::uuid
      else null
    end;

    -- Older app builds could save a region, district, or ward. Resolve that
    -- selection to an active area because the current agents trigger requires
    -- the complete location hierarchy.
    if v_location_id is not null
      and not public.is_valid_agent_location(v_location_id) then
      select l.id
      into v_location_id
      from public.locations l
      where l.is_active
        and l.location_type = 'area'::public.location_type
        and (
          public.location_ancestor_id(l.id, 'ward'::public.location_type) = v_location_id
          or public.location_ancestor_id(l.id, 'district'::public.location_type) = v_location_id
          or public.location_ancestor_id(l.id, 'region'::public.location_type) = v_location_id
        )
      order by l.name, l.id
      limit 1;
    end if;

    -- Incomplete legacy/test metadata cannot satisfy the current location
    -- integrity rule. Leave it untouched instead of aborting valid backfills.
    if v_location_id is null then
      continue;
    end if;

    insert into public.profiles (
      id, full_name, phone_number, preferred_language, username,
      account_email, account_email_confirmed_at
    )
    values (
      v_user.id,
      coalesce(nullif(btrim(v_user.metadata ->> 'full_name'), ''), 'KODIMALI User'),
      nullif(btrim(v_user.metadata ->> 'phone_number'), ''),
      coalesce(nullif(btrim(v_user.metadata ->> 'preferred_language'), ''), 'sw'),
      public.build_manage_username_candidate(
        v_user.metadata ->> 'username',
        v_user.metadata ->> 'full_name',
        v_user.email,
        v_user.metadata ->> 'phone_number',
        v_user.id
      ),
      nullif(lower(btrim(v_user.email)), ''),
      v_user.email_confirmed_at
    )
    on conflict (id) do update set
      phone_number = coalesce(excluded.phone_number, public.profiles.phone_number),
      account_email = excluded.account_email,
      account_email_confirmed_at = excluded.account_email_confirmed_at,
      updated_at = timezone('utc', now());

    insert into public.user_roles (profile_id, role)
    values (v_user.id, 'agent'::public.app_role)
    on conflict (profile_id, role) do nothing;

    insert into public.agents (
      profile_id, display_name, phone_number, nida_number, location_id,
      business_name, business_description
    )
    values (
      v_user.id,
      coalesce(nullif(btrim(v_user.metadata ->> 'full_name'), ''), 'KODIMALI User'),
      nullif(btrim(v_user.metadata ->> 'phone_number'), ''),
      nullif(upper(btrim(v_user.metadata ->> 'nida_number')), ''),
      v_location_id,
      coalesce(
        nullif(btrim(v_user.metadata ->> 'business_name'), ''),
        nullif(btrim(v_user.metadata ->> 'full_name'), ''),
        'KODIMALI Agent'
      ),
      nullif(btrim(v_user.metadata ->> 'business_description'), '')
    )
    on conflict (profile_id) do update set
      display_name = coalesce(public.agents.display_name, excluded.display_name),
      phone_number = coalesce(public.agents.phone_number, excluded.phone_number),
      nida_number = coalesce(public.agents.nida_number, excluded.nida_number),
      location_id = coalesce(public.agents.location_id, excluded.location_id),
      business_name = coalesce(public.agents.business_name, excluded.business_name),
      business_description = coalesce(
        public.agents.business_description,
        excluded.business_description
      ),
      updated_at = timezone('utc', now())
    returning id into v_agent_id;

    if v_category_id is not null then
      insert into public.agent_service_categories (agent_id, category_id, is_primary)
      values (v_agent_id, v_category_id, true)
      on conflict (agent_id, category_id) do update
      set is_primary = excluded.is_primary;
    end if;
  end loop;
end;
$$;
