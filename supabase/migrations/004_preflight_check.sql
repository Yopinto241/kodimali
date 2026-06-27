-- Run this before applying 004_marketplace_activation_categories_feed.sql.
-- It validates the live schema assumptions that 004 depends on.

do $$
declare
  issues text[] := array[]::text[];
  legacy_private_column_count integer := 0;
  has_private_location_table boolean := false;
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'booking_requests'
      and column_name = 'customer_name'
  ) then
    issues := array_append(
      issues,
      'public.booking_requests.customer_name is missing. Apply the guest-request migration first.'
    );
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'booking_requests'
      and column_name = 'customer_phone_number'
  ) then
    issues := array_append(
      issues,
      'public.booking_requests.customer_phone_number is missing. Apply the guest-request migration first.'
    );
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'booking_requests'
      and column_name = 'request_reference'
  ) then
    issues := array_append(
      issues,
      'public.booking_requests.request_reference is missing. Apply the guest-request migration first.'
    );
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'booking_requests'
      and column_name = 'customer_id'
      and is_nullable = 'NO'
  ) then
    issues := array_append(
      issues,
      'public.booking_requests.customer_id is still NOT NULL. Guest requests require it to be nullable.'
    );
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'booking_requests'
      and column_name = 'requested_start_at'
      and is_nullable = 'NO'
  ) then
    issues := array_append(
      issues,
      'public.booking_requests.requested_start_at is still NOT NULL. Guest requests require it to be nullable.'
    );
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'booking_requests'
      and column_name = 'requested_end_at'
      and is_nullable = 'NO'
  ) then
    issues := array_append(
      issues,
      'public.booking_requests.requested_end_at is still NOT NULL. Guest requests require it to be nullable.'
    );
  end if;

  if exists (
    select 1
    from pg_constraint
    where conname = 'booking_requests_no_confirmed_overlap'
  ) then
    issues := array_append(
      issues,
      'booking_requests_no_confirmed_overlap still exists. Remove the old reservation overlap workflow before 004.'
    );
  end if;

  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'booking_status_history'
  ) then
    issues := array_append(
      issues,
      'public.booking_status_history is missing.'
    );
  end if;

  select count(*)
  into legacy_private_column_count
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'listings'
    and column_name in ('exact_address', 'map_pin_latitude', 'map_pin_longitude');

  select exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'listing_private_locations'
  )
  into has_private_location_table;

  if legacy_private_column_count not in (0, 3) then
    issues := array_append(
      issues,
      'public.listings private-location columns are in a partial state. Expected either all 3 legacy columns or none of them.'
    );
  end if;

  if not has_private_location_table and legacy_private_column_count = 0 then
    issues := array_append(
      issues,
      'No supported private-location source found. Expected public.listing_private_locations or the legacy listings exact_address/map_pin_* columns.'
    );
  end if;

  if array_length(issues, 1) is not null then
    raise exception E'004 preflight failed:\n- %', array_to_string(issues, E'\n- ');
  end if;
end
$$;

select
  '004 preflight passed' as status,
  current_timestamp as checked_at;
