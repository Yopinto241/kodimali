alter table public.booking_requests
  add column if not exists customer_phone_normalized text,
  add column if not exists customer_email_normalized text;

alter table public.booking_requests
  alter column customer_phone_number drop not null,
  alter column customer_email drop not null,
  alter column customer_phone_normalized drop not null,
  alter column customer_email_normalized drop not null;

create or replace function public.normalize_contact_phone(raw_phone text)
returns text
language sql
immutable
as $$
  select nullif(regexp_replace(btrim(coalesce(raw_phone, '')), '[^\d+]', '', 'g'), '');
$$;

create or replace function public.normalize_contact_email(raw_email text)
returns text
language sql
immutable
as $$
  select nullif(lower(btrim(coalesce(raw_email, ''))), '');
$$;

create or replace function public.booking_request_contact_label(
  raw_phone text,
  raw_email text,
  raw_name text default null
)
returns text
language sql
immutable
as $$
  select coalesce(
    public.normalize_contact_phone(raw_phone),
    public.normalize_contact_email(raw_email),
    nullif(btrim(coalesce(raw_name, '')), ''),
    'Guest'
  );
$$;

alter table public.booking_requests disable trigger booking_requests_updated_at;
alter table public.booking_requests disable trigger guard_guest_booking_request_update;

update public.booking_requests
set
  customer_email = coalesce(
    public.normalize_contact_email(customer_email),
    case
      when customer_phone_number ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
      then public.normalize_contact_email(customer_phone_number)
      else null
    end
  ),
  customer_phone_number = case
    when customer_phone_number ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then null
    else nullif(btrim(customer_phone_number), '')
  end;

update public.booking_requests
set
  customer_phone_normalized = public.normalize_contact_phone(customer_phone_number),
  customer_email_normalized = public.normalize_contact_email(customer_email);

alter table public.booking_requests enable trigger booking_requests_updated_at;
alter table public.booking_requests enable trigger guard_guest_booking_request_update;

create index if not exists idx_booking_requests_listing_phone_lookup
  on public.booking_requests (listing_id, customer_phone_normalized, created_at desc)
  where customer_phone_normalized is not null;

create index if not exists idx_booking_requests_listing_email_lookup
  on public.booking_requests (listing_id, customer_email_normalized, created_at desc)
  where customer_email_normalized is not null;

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

  new.customer_email := public.normalize_contact_email(new.customer_email);
  new.customer_phone_number := nullif(btrim(new.customer_phone_number), '');
  new.customer_phone_normalized := public.normalize_contact_phone(
    new.customer_phone_number
  );
  new.customer_email_normalized := public.normalize_contact_email(
    new.customer_email
  );
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

  if new.customer_phone_normalized is not null
     and length(new.customer_phone_normalized) < 8
  then
    raise exception 'customer_phone_number is invalid';
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
          new.customer_phone_normalized is not null
          and br.customer_phone_normalized = new.customer_phone_normalized
        )
        or (
          new.customer_email_normalized is not null
          and br.customer_email_normalized = new.customer_email_normalized
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

create or replace function public.guard_guest_booking_request_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agent_id uuid;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if public.is_admin(auth.uid()) then
    if new.listing_id is distinct from old.listing_id
      or new.agent_id is distinct from old.agent_id
      or new.customer_id is distinct from old.customer_id
      or new.customer_name is distinct from old.customer_name
      or new.customer_phone_number is distinct from old.customer_phone_number
      or new.customer_phone_normalized is distinct from old.customer_phone_normalized
      or new.customer_email is distinct from old.customer_email
      or new.customer_email_normalized is distinct from old.customer_email_normalized
      or new.request_reference is distinct from old.request_reference
      or new.requested_start_at is distinct from old.requested_start_at
      or new.requested_end_at is distinct from old.requested_end_at
      or new.guest_count is distinct from old.guest_count
      or new.request_message is distinct from old.request_message
      or new.requested_service_codes is distinct from old.requested_service_codes
    then
      raise exception 'Admin cannot change immutable guest-request fields';
    end if;
  else
    select a.id
    into v_agent_id
    from public.agents a
    where a.profile_id = auth.uid()
      and a.account_status = 'active'::public.agent_account_status
    limit 1;

    if v_agent_id is null or v_agent_id <> old.agent_id then
      raise exception 'Only the assigned active agent can update this request';
    end if;

    if new.listing_id is distinct from old.listing_id
      or new.agent_id is distinct from old.agent_id
      or new.customer_id is distinct from old.customer_id
      or new.customer_name is distinct from old.customer_name
      or new.customer_phone_number is distinct from old.customer_phone_number
      or new.customer_phone_normalized is distinct from old.customer_phone_normalized
      or new.customer_email is distinct from old.customer_email
      or new.customer_email_normalized is distinct from old.customer_email_normalized
      or new.request_reference is distinct from old.request_reference
      or new.requested_start_at is distinct from old.requested_start_at
      or new.requested_end_at is distinct from old.requested_end_at
      or new.guest_count is distinct from old.guest_count
      or new.request_message is distinct from old.request_message
      or new.requested_service_codes is distinct from old.requested_service_codes
      or new.admin_override is distinct from old.admin_override
    then
      raise exception 'Active agents can update only guest inquiry status fields';
    end if;
  end if;

  new.customer_id := null;
  new.listing_id := old.listing_id;
  new.agent_id := old.agent_id;
  new.customer_name := old.customer_name;
  new.customer_phone_number := old.customer_phone_number;
  new.customer_phone_normalized := old.customer_phone_normalized;
  new.customer_email := old.customer_email;
  new.customer_email_normalized := old.customer_email_normalized;
  new.request_reference := old.request_reference;
  new.requested_start_at := old.requested_start_at;
  new.requested_end_at := old.requested_end_at;
  new.guest_count := old.guest_count;
  new.request_message := old.request_message;
  new.requested_service_codes := old.requested_service_codes;

  if new.booking_status is distinct from old.booking_status
     and old.first_agent_response_at is null then
    new.first_agent_response_at := timezone('utc', now());
  else
    new.first_agent_response_at := old.first_agent_response_at;
  end if;

  return new;
end;
$$;

create or replace function public.record_guest_booking_status_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.booking_status_history (
      booking_request_id,
      status,
      changed_by,
      reason
    )
    values (
      new.id,
      new.booking_status,
      auth.uid(),
      'Guest inquiry created'
    );
    return new;
  end if;

  if new.booking_status is distinct from old.booking_status then
    insert into public.booking_status_history (
      booking_request_id,
      status,
      changed_by,
      reason
    )
    values (
      new.id,
      new.booking_status,
      auth.uid(),
      'Guest inquiry status updated'
    );
  end if;

  return new;
end;
$$;

create or replace function public.create_guest_booking_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agent_profile_id uuid;
  v_listing_title text;
  v_contact text;
begin
  select a.profile_id, l.title
  into v_agent_profile_id, v_listing_title
  from public.agents a
  join public.listings l on l.id = new.listing_id
  where a.id = new.agent_id
  limit 1;

  if v_agent_profile_id is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    v_contact := public.booking_request_contact_label(
      new.customer_phone_number,
      new.customer_email,
      new.customer_name
    );

    insert into public.notifications (
      user_id,
      booking_request_id,
      type,
      title,
      body,
      payload
    )
    values (
      v_agent_profile_id,
      new.id,
      'booking_created'::public.notification_type,
      'New inquiry received',
      coalesce(v_listing_title, 'Listing') || ' | ' || coalesce(new.customer_name, 'Guest') || ' | ' || v_contact,
      jsonb_build_object(
        'bookingId', new.id,
        'listingId', new.listing_id,
        'requestReference', new.request_reference
      )
    );
    return new;
  end if;

  if new.booking_status is distinct from old.booking_status
     and public.is_admin(auth.uid()) then
    insert into public.notifications (
      user_id,
      booking_request_id,
      type,
      title,
      body,
      payload
    )
    values (
      v_agent_profile_id,
      new.id,
      'booking_status_changed'::public.notification_type,
      'Inquiry status updated',
      coalesce(v_listing_title, 'Listing') || ' | status ' || new.booking_status::text,
      jsonb_build_object(
        'bookingId', new.id,
        'listingId', new.listing_id,
        'requestReference', new.request_reference,
        'bookingStatus', new.booking_status::text
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists record_guest_inquiry_history on public.booking_requests;
drop trigger if exists notify_agent_of_inquiry on public.booking_requests;
drop trigger if exists record_guest_booking_status_history on public.booking_requests;
drop trigger if exists create_guest_booking_notification on public.booking_requests;

drop function if exists public.record_guest_inquiry_history();
drop function if exists public.notify_agent_of_inquiry();

create trigger record_guest_booking_status_history
after insert or update of booking_status on public.booking_requests
for each row execute function public.record_guest_booking_status_history();

create trigger create_guest_booking_notification
after insert or update of booking_status on public.booking_requests
for each row execute function public.create_guest_booking_notification();
