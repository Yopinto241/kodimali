insert into public.asset_categories (
  name,
  slug,
  description,
  icon_key,
  display_order,
  is_active,
  home_feed_weight,
  field_schema
)
values
  (
    'Apartment',
    'apartment',
    'Serviced apartments, flats, and short-stay homes for local and international guests.',
    'apartment',
    2,
    true,
    9,
    '[
      {"key":"bedrooms","label":"Bedrooms","type":"number","required":true},
      {"key":"bathrooms","label":"Bathrooms","type":"number","required":true},
      {"key":"furnished","label":"Furnished","type":"boolean","required":true},
      {"key":"max_guests","label":"Max guests","type":"number"},
      {"key":"floor_number","label":"Floor number","type":"number"},
      {"key":"total_floors","label":"Total floors","type":"number"},
      {"key":"balcony","label":"Balcony","type":"boolean"},
      {"key":"lift","label":"Lift","type":"boolean"},
      {"key":"parking","label":"Parking","type":"boolean"},
      {"key":"security","label":"Security","type":"boolean"},
      {"key":"service_charge","label":"Service charge","type":"number"},
      {"key":"minimum_stay_nights","label":"Minimum stay nights","type":"number"},
      {"key":"check_in_time","label":"Check-in time","type":"text"},
      {"key":"check_out_time","label":"Check-out time","type":"text"},
      {"key":"wifi_available","label":"WiFi available","type":"boolean"},
      {"key":"food_available","label":"Food available","type":"boolean"},
      {"key":"transport_available","label":"Transport available","type":"boolean"},
      {"key":"cleaning_available","label":"Cleaning available","type":"boolean"},
      {"key":"laundry_available","label":"Laundry available","type":"boolean"},
      {"key":"water_included","label":"Water included","type":"boolean"},
      {"key":"electricity_included","label":"Electricity included","type":"boolean"},
      {"key":"power_backup","label":"Power backup","type":"boolean"},
      {"key":"other_services","label":"Other services","type":"textarea"},
      {"key":"booking_notes","label":"Booking notes","type":"textarea"}
    ]'::jsonb
  )
on conflict (slug) do update
set
  name = excluded.name,
  description = excluded.description,
  icon_key = excluded.icon_key,
  display_order = excluded.display_order,
  is_active = excluded.is_active,
  home_feed_weight = excluded.home_feed_weight,
  field_schema = excluded.field_schema;

update public.asset_categories
set display_order = 3
where slug = 'car';

update public.asset_categories
set display_order = 4
where slug = 'motorcycle';

update public.asset_categories
set display_order = 5
where slug = 'office';

update public.asset_categories
set display_order = 6
where slug = 'meeting-hall';

update public.asset_categories
set display_order = 7
where slug = 'ceremony-hall';

update public.asset_categories
set display_order = 8
where slug = 'equipment';

update public.asset_categories
set display_order = 9
where slug = 'farms';

update public.asset_categories
set display_order = 10
where slug = 'other-asset';

alter table public.booking_requests
  add column if not exists guest_count integer,
  add column if not exists requested_service_codes jsonb not null default '[]'::jsonb;

create or replace function public.prepare_guest_booking_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_listing public.listings%rowtype;
  v_category_slug text;
  v_has_contact boolean;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;

  if new.customer_name is null or btrim(new.customer_name) = '' then
    raise exception 'customer_name is required';
  end if;

  new.customer_email := nullif(lower(btrim(new.customer_email)), '');
  new.customer_phone_number := nullif(btrim(new.customer_phone_number), '');
  new.request_message := nullif(btrim(new.request_message), '');
  new.requested_service_codes := coalesce(new.requested_service_codes, '[]'::jsonb);

  v_has_contact := new.customer_email is not null or new.customer_phone_number is not null;
  if not v_has_contact then
    raise exception 'Provide at least one contact method';
  end if;

  if new.customer_email is not null
     and (
       position('@' in new.customer_email) <= 1
       or position('.' in split_part(new.customer_email, '@', 2)) <= 1
     )
  then
    raise exception 'customer_email is invalid';
  end if;

  if new.guest_count is not null and new.guest_count < 1 then
    raise exception 'guest_count must be at least 1';
  end if;

  select l.*
  into v_listing
  from public.listings l
  where l.id = new.listing_id;

  select c.slug
  into v_category_slug
  from public.listings l
  join public.asset_categories c on c.id = l.category_id
  where l.id = new.listing_id;

  if v_listing.id is null then
    raise exception 'Listing was not found';
  end if;

  if not public.is_listing_public(new.listing_id) then
    raise exception 'Listing is not accepting public requests';
  end if;

  if exists (
    select 1
    from public.booking_requests br
    where br.listing_id = new.listing_id
      and (
        (
          new.customer_phone_number is not null
          and br.customer_phone_number = new.customer_phone_number
        )
        or (
          new.customer_email is not null
          and lower(coalesce(br.customer_email, '')) = new.customer_email
        )
      )
      and br.created_at >= timezone('utc', now()) - interval '10 minutes'
  ) then
    raise exception 'A recent request from this contact already exists for this listing';
  end if;

  if v_category_slug = 'apartment' then
    if new.customer_email is null then
      raise exception 'customer_email is required for apartment bookings';
    end if;

    if new.requested_start_at is null or new.requested_end_at is null then
      raise exception 'requested_start_at and requested_end_at are required for apartment bookings';
    end if;

    if new.requested_end_at <= new.requested_start_at then
      raise exception 'requested_end_at must be after requested_start_at';
    end if;

    if exists (
      select 1
      from public.booking_requests br
      where br.listing_id = new.listing_id
        and br.booking_status not in (
          'completed'::public.booking_status,
          'cancelled'::public.booking_status,
          'rejected'::public.booking_status,
          'no_response'::public.booking_status
        )
        and br.requested_start_at is not null
        and br.requested_end_at is not null
        and new.requested_start_at < br.requested_end_at
        and new.requested_end_at > br.requested_start_at
    ) then
      raise exception 'The apartment is not available for the selected dates';
    end if;
  else
    new.requested_start_at := null;
    new.requested_end_at := null;
    new.guest_count := null;
    new.requested_service_codes := '[]'::jsonb;
  end if;

  new.customer_id := null;
  new.agent_id := v_listing.agent_id;
  new.booking_status := 'new'::public.booking_status;
  new.request_reference := coalesce(
    new.request_reference,
    public.generate_booking_request_reference()
  );

  return new;
end;
$$;
