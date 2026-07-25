-- Run this after applying 004_marketplace_activation_categories_feed.sql.
-- It checks the final KODIMALI v1 marketplace rules and provides role-based
-- verification queries for the security-sensitive behaviors.

do $$
declare
  fn_def text;
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'listings'
      and column_name in ('exact_address', 'map_pin_latitude', 'map_pin_longitude')
  ) then
    raise exception 'public.listings must not keep exact_address/map_pin_* columns after 004';
  end if;

  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'listing_private_locations'
  ) then
    raise exception 'public.listing_private_locations is missing';
  end if;

  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'listings',
        'listing_media',
        'property_details',
        'vehicle_details',
        'venue_details',
        'farm_details',
        'booking_requests'
      )
      and cmd = 'SELECT'
      and policyname in (
        'listings_public_select_approved',
        'listing_media_follow_listing_visibility_select',
        'property_details_follow_listing_visibility',
        'vehicle_details_follow_listing_visibility',
        'venue_details_follow_listing_visibility',
        'farm_details_follow_listing_visibility',
        'booking_requests_customer_agent_admin_select'
      )
  ) then
    raise exception 'Legacy public SELECT policies still exist on protected tables';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'listing_media_public_listing_read_object'
      and qual ilike '%is_public_listing_media_object%'
  ) then
    raise exception 'Safe storage.objects policy for public listing media is missing';
  end if;

  if exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'agents_manage_own_listing_media_files'
  ) then
    raise exception 'agents_manage_own_listing_media_files must be removed';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'booking_requests'
      and policyname = 'booking_requests_active_agent_admin_select'
      and qual ilike '%is_agent_active%'
  ) then
    raise exception 'booking_requests_active_agent_admin_select must require active-agent access';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'booking_requests'
      and policyname = 'booking_requests_active_agent_admin_update'
      and qual ilike '%is_agent_active%'
      and with_check ilike '%is_agent_active%'
  ) then
    raise exception 'booking_requests_active_agent_admin_update must require active-agent access';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'booking_status_history'
      and policyname = 'booking_history_visible_to_active_agent_or_admin'
      and qual ilike '%is_agent_active%'
  ) then
    raise exception 'booking_history_visible_to_active_agent_or_admin is missing';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'agents'
      and policyname = 'agents_self_safe_update'
      and qual ilike '%account_status = ''active''%'
  ) then
    raise exception 'agents_self_safe_update must allow self-update only for active agents';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'agent_documents'
      and policyname = 'agent_documents_owner_or_admin_all'
      and qual ilike '%can_manage_agent_documents%'
  ) then
    raise exception 'agent_documents_owner_or_admin_all must be gated by can_manage_agent_documents()';
  end if;

  if not exists (
    select 1
    from storage.buckets
    where id = 'listing-media'
      and public = false
      and file_size_limit = 31457280
      and allowed_mime_types @> array[
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/gif',
        'image/heic',
        'image/heif',
        'video/mp4',
        'video/quicktime',
        'video/x-m4v',
        'video/webm',
        'video/x-msvideo',
        'video/x-matroska'
      ]::text[]
  ) then
    raise exception 'listing-media bucket must stay private with the expected size and mime-type limits';
  end if;

  if not exists (
    select 1
    from storage.buckets
    where id = 'platform-promotions'
      and public = false
  ) then
    raise exception 'platform-promotions bucket must stay private';
  end if;

  select pg_get_functiondef('public.get_public_listing_detail(uuid)'::regprocedure)
  into fn_def;

  if fn_def ilike '%exact_address%'
    or fn_def ilike '%map_pin_latitude%'
    or fn_def ilike '%map_pin_longitude%'
    or fn_def ilike '%owner_id%'
    or fn_def ilike '%inquiry_count%'
  then
    raise exception 'get_public_listing_detail exposes private or disallowed fields';
  end if;

  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'marketplace_settings'
  ) then
    raise exception 'marketplace_settings table must exist for admin contact-payment toggle';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'marketplace_settings'
      and column_name = 'contact_payments_enabled'
      and data_type = 'boolean'
  ) then
    raise exception 'marketplace_settings.contact_payments_enabled boolean is required';
  end if;

  if not exists (
    select 1
    from pg_proc
    where oid = 'public.contact_payments_enabled()'::regprocedure
      and prosecdef = true
  ) then
    raise exception 'contact_payments_enabled() must exist as a SECURITY DEFINER helper';
  end if;

  if fn_def not ilike '%contact_payments_enabled()%'
    or fn_def not ilike '%then null::text%'
    or fn_def not ilike '%else nullif(btrim(a.phone_number), '''')%'
  then
    raise exception 'get_public_listing_detail must hide or reveal agent_phone_number from contact_payments_enabled()';
  end if;

  select pg_get_functiondef('public.get_public_home_feed(integer, integer, uuid, uuid, double precision, double precision, text)'::regprocedure)
  into fn_def;

  if fn_def ilike '%inquiry_count%'
    or fn_def ilike '%distance_score%'
  then
    raise exception 'get_public_home_feed must not return inquiry_count or distance_score';
  end if;

  select pg_get_functiondef('public.prepare_guest_booking_request()'::regprocedure)
  into fn_def;

  if fn_def not ilike '%is_listing_public%' then
    raise exception 'prepare_guest_booking_request must validate listings with is_listing_public()';
  end if;

  if not exists (
    select 1
    from pg_proc
    where proname = 'can_manage_agent_documents'
      and prosecdef = true
  ) then
    raise exception 'can_manage_agent_documents must exist as a SECURITY DEFINER helper';
  end if;
end
$$;

-- Replace the UUIDs and object names below with real values from your project.
-- These queries prove the role-based runtime behavior after 004.

-- 1. Anonymous visitor cannot select public.listings directly.
begin;
set local role anon;
set local "request.jwt.claim.role" = 'anon';
select count(*) as anon_direct_listing_rows from public.listings;
rollback;

-- 2. Anonymous visitor cannot read private address / GPS from listing_private_locations.
begin;
set local role anon;
set local "request.jwt.claim.role" = 'anon';
select count(*) as anon_private_location_rows from public.listing_private_locations;
rollback;

-- 3. Anonymous visitor can read media only for a currently public listing.
-- Replace with an existing storage.objects.name for an active public listing.
begin;
set local role anon;
set local "request.jwt.claim.role" = 'anon';
select count(*) as anon_public_media_rows
from storage.objects
where bucket_id = 'listing-media'
  and name = 'ACTIVE_AGENT_UUID/ACTIVE_LISTING_UUID/cover.jpg';
rollback;

-- 4. A removed or no-longer-public listing's media must not resolve publicly.
-- Replace with an existing storage.objects.name from a removed/inactive/suspended listing.
begin;
set local role anon;
set local "request.jwt.claim.role" = 'anon';
select count(*) as anon_removed_media_rows
from storage.objects
where bucket_id = 'listing-media'
  and name = 'REMOVED_AGENT_UUID/REMOVED_LISTING_UUID/cover.jpg';
rollback;

-- 5. Inactive agent cannot read booking requests.
begin;
set local role authenticated;
set local "request.jwt.claim.role" = 'authenticated';
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';
select count(*) as inactive_agent_visible_requests from public.booking_requests;
rollback;

-- 6. Inactive agent cannot update booking status.
begin;
set local role authenticated;
set local "request.jwt.claim.role" = 'authenticated';
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';
update public.booking_requests
set booking_status = 'contacted'::public.booking_status
where id = '00000000-0000-0000-0000-000000000101'::uuid
returning id, booking_status;
rollback;

-- 7. Active agent can read only assigned booking requests.
begin;
set local role authenticated;
set local "request.jwt.claim.role" = 'authenticated';
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000002';
select id, listing_id, agent_id, request_reference, customer_name, customer_phone_number
from public.booking_requests
order by created_at desc;
rollback;

-- 8. Active agent can read only history for assigned requests.
begin;
set local role authenticated;
set local "request.jwt.claim.role" = 'authenticated';
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000002';
select booking_request_id, status, created_at
from public.booking_status_history
order by created_at desc;
rollback;

-- 9. Public RPCs remain the only supported public listing read path.
select *
from public.get_public_home_feed(
  p_limit => 5,
  p_page => 0,
  p_session_seed => 'verification-home'
);

select *
from public.get_public_listings(
  p_category_slug => null,
  p_search_text => null,
  p_region_id => null,
  p_district_id => null,
  p_limit => 5,
  p_page => 0,
  p_session_seed => 'verification-list'
);

select *
from public.get_public_listing_detail(
  p_listing_id => '00000000-0000-0000-0000-000000000201'::uuid
);
