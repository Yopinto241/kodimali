create or replace function public.search_admin_agents(
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
    where (
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

grant execute on function public.search_admin_agents(
  text,
  text,
  text,
  integer,
  integer
) to authenticated;
