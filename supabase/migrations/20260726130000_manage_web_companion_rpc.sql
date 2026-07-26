-- Shared management commands for Manage Mobile and the browser companion.
-- Authorization lives here so every client follows the same rules.

create or replace function public.get_manage_dashboard_counts()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agent_id uuid;
  v_is_admin boolean := public.is_admin(auth.uid());
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not v_is_admin then
    select id into v_agent_id from public.agents where profile_id = auth.uid();
    if v_agent_id is null then raise exception 'Management access required'; end if;
  end if;

  select jsonb_build_object(
    'listings', count(*),
    'active_listings', count(*) filter (where status = 'active'::public.listing_status)
  ) into v_result
  from public.listings
  where v_is_admin or agent_id = v_agent_id;

  return v_result || jsonb_build_object(
    'open_requests', (
      select count(*) from public.booking_requests
      where (v_is_admin or agent_id = v_agent_id)
        and booking_status not in (
          'completed'::public.booking_status, 'cancelled'::public.booking_status,
          'rejected'::public.booking_status
        )
    ),
    'agents', case when v_is_admin then (select count(*) from public.agents) else 1 end
  );
end;
$$;

create or replace function public.manage_update_booking_status(
  p_booking_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agent_id uuid;
  v_owner_agent_id uuid;
  v_status public.booking_status;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  v_status := p_status::public.booking_status;
  select agent_id into v_owner_agent_id from public.booking_requests where id = p_booking_id;
  if v_owner_agent_id is null then raise exception 'Request not found'; end if;
  if not public.is_admin(auth.uid()) then
    select id into v_agent_id from public.agents where profile_id = auth.uid();
    if v_agent_id is distinct from v_owner_agent_id then raise exception 'Not authorized'; end if;
  end if;
  update public.booking_requests set booking_status = v_status where id = p_booking_id;
end;
$$;

create or replace function public.manage_update_listing_basic(
  p_listing_id uuid,
  p_values jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agent_id uuid;
  v_owner_agent_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select agent_id into v_owner_agent_id from public.listings where id = p_listing_id;
  if v_owner_agent_id is null then raise exception 'Listing not found'; end if;
  if not public.is_admin(auth.uid()) then
    select id into v_agent_id from public.agents where profile_id = auth.uid();
    if v_agent_id is distinct from v_owner_agent_id then raise exception 'Not authorized'; end if;
  end if;
  if coalesce(btrim(p_values ->> 'title'), '') = '' then raise exception 'Title is required'; end if;
  if char_length(btrim(coalesce(p_values ->> 'description', ''))) < 10 then
    raise exception 'Description must contain at least 10 characters';
  end if;
  update public.listings set
    title = btrim(p_values ->> 'title'),
    description = btrim(p_values ->> 'description'),
    price_amount = (p_values ->> 'price_amount')::numeric,
    availability_status = (p_values ->> 'availability_status')::public.availability_status,
    listing_attributes = coalesce(p_values -> 'listing_attributes', listing_attributes)
  where id = p_listing_id;
end;
$$;

create or replace function public.manage_save_category_fields(
  p_category_id uuid,
  p_field_schema jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'Administrator access required'; end if;
  update public.asset_categories set field_schema = p_field_schema where id = p_category_id;
  if not found then raise exception 'Category not found'; end if;
end;
$$;

revoke all on function public.get_manage_dashboard_counts() from public;
revoke all on function public.manage_update_booking_status(uuid, text) from public;
revoke all on function public.manage_update_listing_basic(uuid, jsonb) from public;
revoke all on function public.manage_save_category_fields(uuid, jsonb) from public;
grant execute on function public.get_manage_dashboard_counts() to authenticated;
grant execute on function public.manage_update_booking_status(uuid, text) to authenticated;
grant execute on function public.manage_update_listing_basic(uuid, jsonb) to authenticated;
grant execute on function public.manage_save_category_fields(uuid, jsonb) to authenticated;
