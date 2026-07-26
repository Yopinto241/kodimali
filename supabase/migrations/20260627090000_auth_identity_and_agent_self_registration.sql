alter table public.profiles
  add column if not exists username text,
  add column if not exists account_email text,
  add column if not exists account_email_confirmed_at timestamptz;

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

update public.profiles p
set
  account_email = nullif(lower(btrim(u.email)), ''),
  account_email_confirmed_at = u.email_confirmed_at
from auth.users u
where u.id = p.id
  and (
    p.account_email is distinct from nullif(lower(btrim(u.email)), '')
    or p.account_email_confirmed_at is distinct from u.email_confirmed_at
  );

with username_candidates as (
  select
    p.id,
    public.build_manage_username_candidate(
      p.username,
      p.full_name,
      coalesce(p.account_email, u.email),
      p.phone_number,
      p.id
    ) as base_username
  from public.profiles p
  left join auth.users u on u.id = p.id
),
ranked_usernames as (
  select
    id,
    base_username,
    row_number() over (partition by base_username order by id) as duplicate_rank
  from username_candidates
),
resolved_usernames as (
  select
    id,
    case
      when duplicate_rank = 1 then base_username
      else left(base_username, 32 - length('_' || duplicate_rank::text))
        || '_' || duplicate_rank::text
    end as final_username
  from ranked_usernames
)
update public.profiles p
set username = r.final_username
from resolved_usernames r
where r.id = p.id
  and p.username is distinct from r.final_username;

alter table public.profiles
  drop constraint if exists profiles_username_format;

alter table public.profiles
  add constraint profiles_username_format
  check (username is null or username ~ '^[a-z0-9_]{3,32}$');

create unique index if not exists profiles_username_unique
  on public.profiles (username)
  where username is not null;

create unique index if not exists profiles_account_email_unique
  on public.profiles (lower(account_email))
  where account_email is not null;

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

drop trigger if exists handle_auth_user_created on auth.users;
create trigger handle_auth_user_created
after insert on auth.users
for each row execute function public.handle_auth_user_created();

create or replace function public.handle_auth_user_updated()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  update public.profiles
  set
    username = coalesce(
      username,
      public.build_manage_username_candidate(
        v_metadata ->> 'username',
        coalesce(
          nullif(btrim(v_metadata ->> 'full_name'), ''),
          public.profiles.full_name
        ),
        new.email,
        coalesce(
          nullif(btrim(v_metadata ->> 'phone_number'), ''),
          public.profiles.phone_number
        ),
        new.id
      )
    ),
    account_email = nullif(lower(btrim(new.email)), ''),
    account_email_confirmed_at = new.email_confirmed_at,
    updated_at = timezone('utc', now())
  where id = new.id;

  return new;
end;
$$;

drop trigger if exists handle_auth_user_updated on auth.users;
create trigger handle_auth_user_updated
after update of email, email_confirmed_at, raw_user_meta_data on auth.users
for each row execute function public.handle_auth_user_updated();

create or replace function public.resolve_manage_login_identifier(
  p_identifier text
)
returns table (
  profile_id uuid,
  username text,
  account_email text,
  matched_by text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_identifier text := lower(btrim(coalesce(p_identifier, '')));
  v_phone text := public.normalize_manage_phone(p_identifier);
  v_exact_match_exists boolean := false;
  v_phone_match_count integer := 0;
begin
  if v_identifier = '' then
    return;
  end if;

  select exists(
    select 1
    from public.profiles p
    where p.username = v_identifier
       or lower(coalesce(p.account_email, '')) = v_identifier
  )
  into v_exact_match_exists;

  if not v_exact_match_exists and v_phone is not null then
    select count(*)
    into v_phone_match_count
    from public.profiles p
    where public.normalize_manage_phone(p.phone_number) = v_phone;

    if v_phone_match_count > 1 then
      raise exception 'Phone number matches multiple accounts. Use username or email.';
    end if;
  end if;

  return query
  select
    p.id,
    p.username,
    p.account_email,
    case
      when p.username = v_identifier then 'username'
      when lower(coalesce(p.account_email, '')) = v_identifier then 'email'
      else 'phone'
    end as matched_by
  from public.profiles p
  where p.username = v_identifier
     or lower(coalesce(p.account_email, '')) = v_identifier
     or (
       v_phone is not null
       and public.normalize_manage_phone(p.phone_number) = v_phone
     )
  order by
    case
      when p.username = v_identifier then 1
      when lower(coalesce(p.account_email, '')) = v_identifier then 2
      else 3
    end,
    p.id
  limit 1;
end;
$$;

revoke all on function public.resolve_manage_login_identifier(text)
from public, anon, authenticated;
grant execute on function public.resolve_manage_login_identifier(text)
to anon, authenticated, service_role;
