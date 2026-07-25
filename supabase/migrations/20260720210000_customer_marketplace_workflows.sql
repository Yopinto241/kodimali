begin;

-- Customer accounts are optional. Public/guest requests continue to have a
-- null customer_id, while authenticated customers can create or claim a
-- request without changing the agent copied from the listing.

do $$
begin
  alter type public.notification_type add value if not exists 'message_received';
  alter type public.notification_type add value if not exists 'viewing_updated';
  alter type public.notification_type add value if not exists 'review_received';
end
$$;

-- PostgreSQL requires newly-added enum values to be committed before they can
-- be used by notification trigger functions later in this migration.
commit;
begin;

alter table public.booking_requests
  drop constraint if exists booking_requests_customer_id_fkey;

alter table public.booking_requests
  add constraint booking_requests_customer_id_fkey
  foreign key (customer_id)
  references public.profiles (id)
  on delete set null;

create or replace function public.ensure_customer_role_for_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_roles (profile_id, role)
  values (new.id, 'customer'::public.app_role)
  on conflict (profile_id, role) do nothing;

  return new;
end;
$$;

drop trigger if exists ensure_customer_role_for_profile on public.profiles;
create trigger ensure_customer_role_for_profile
after insert on public.profiles
for each row execute function public.ensure_customer_role_for_profile();

insert into public.user_roles (profile_id, role)
select p.id, 'customer'::public.app_role
from public.profiles p
on conflict (profile_id, role) do nothing;

create or replace function public.is_booking_participant(
  p_booking_request_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    exists (
      select 1
      from public.booking_requests br
      left join public.agents a on a.id = br.agent_id
      where br.id = p_booking_request_id
        and p_user_id is not null
        and p_user_id = auth.uid()
        and (
          br.customer_id = p_user_id
          or (
            a.profile_id = p_user_id
            and a.account_status = 'active'::public.agent_account_status
          )
        )
    ),
    false
  );
$$;

create or replace function public.is_booking_assigned_agent(
  p_booking_request_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    exists (
      select 1
      from public.booking_requests br
      join public.agents a on a.id = br.agent_id
      where br.id = p_booking_request_id
        and p_user_id is not null
        and p_user_id = auth.uid()
        and a.profile_id = p_user_id
        and a.account_status = 'active'::public.agent_account_status
    ),
    false
  );
$$;

-- Keep all existing guest-request immutability rules. The only new mutation is
-- a one-time null -> auth.uid() linkage performed by the secure RPCs below.
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

  if old.customer_id is null
     and new.customer_id = auth.uid()
     and new.listing_id is not distinct from old.listing_id
     and new.agent_id is not distinct from old.agent_id
     and new.customer_name is not distinct from old.customer_name
     and new.customer_phone_number is not distinct from old.customer_phone_number
     and new.customer_phone_normalized is not distinct from old.customer_phone_normalized
     and new.customer_email is not distinct from old.customer_email
     and new.customer_email_normalized is not distinct from old.customer_email_normalized
     and new.request_reference is not distinct from old.request_reference
     and new.requested_start_at is not distinct from old.requested_start_at
     and new.requested_end_at is not distinct from old.requested_end_at
     and new.guest_count is not distinct from old.guest_count
     and new.request_message is not distinct from old.request_message
     and new.requested_service_codes is not distinct from old.requested_service_codes
     and new.booking_status is not distinct from old.booking_status
     and new.agent_response_due_at is not distinct from old.agent_response_due_at
     and new.first_agent_response_at is not distinct from old.first_agent_response_at
     and new.admin_override is not distinct from old.admin_override
  then
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

  new.customer_id := old.customer_id;
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

drop policy if exists "booking_requests_active_agent_admin_select"
on public.booking_requests;
drop policy if exists "booking_requests_participant_admin_select"
on public.booking_requests;
create policy "booking_requests_participant_admin_select"
on public.booking_requests
for select
using (
  customer_id = auth.uid()
  or public.is_admin()
  or public.is_booking_assigned_agent(id)
);

drop policy if exists "booking_requests_active_agent_admin_update"
on public.booking_requests;
drop policy if exists "booking_requests_assigned_agent_admin_update"
on public.booking_requests;
create policy "booking_requests_assigned_agent_admin_update"
on public.booking_requests
for update
using (public.is_admin() or public.is_booking_assigned_agent(id))
with check (public.is_admin() or public.is_booking_assigned_agent(id));

drop policy if exists "booking_history_visible_to_active_agent_or_admin"
on public.booking_status_history;
drop policy if exists "booking_history_visible_to_participants_or_admin"
on public.booking_status_history;
create policy "booking_history_visible_to_participants_or_admin"
on public.booking_status_history
for select
using (
  public.is_admin()
  or public.is_booking_participant(booking_request_id)
);

create or replace function public.create_authenticated_booking_request(
  p_listing_id uuid,
  p_customer_name text,
  p_customer_phone_number text default null,
  p_customer_email text default null,
  p_requested_start_at timestamptz default null,
  p_requested_end_at timestamptz default null,
  p_guest_count integer default null,
  p_request_message text default null,
  p_requested_service_codes jsonb default '[]'::jsonb
)
returns table (
  booking_request_id uuid,
  request_reference text,
  booking_status text,
  agent_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_booking public.booking_requests%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if not exists (select 1 from public.profiles p where p.id = v_user_id) then
    raise exception 'Customer profile was not found' using errcode = '23503';
  end if;

  insert into public.booking_requests (
    listing_id,
    customer_name,
    customer_phone_number,
    customer_email,
    requested_start_at,
    requested_end_at,
    guest_count,
    request_message,
    requested_service_codes
  )
  values (
    p_listing_id,
    p_customer_name,
    p_customer_phone_number,
    p_customer_email,
    p_requested_start_at,
    p_requested_end_at,
    p_guest_count,
    p_request_message,
    coalesce(p_requested_service_codes, '[]'::jsonb)
  )
  returning * into v_booking;

  update public.booking_requests br
  set customer_id = v_user_id
  where br.id = v_booking.id;

  insert into public.audit_logs (
    actor_id,
    action,
    target_table,
    target_id,
    metadata
  )
  values (
    v_user_id,
    'customer_booking_created',
    'booking_requests',
    v_booking.id,
    jsonb_build_object(
      'listingId', v_booking.listing_id,
      'requestReference', v_booking.request_reference
    )
  );

  return query
  select
    v_booking.id,
    v_booking.request_reference,
    v_booking.booking_status::text,
    v_booking.agent_id;
end;
$$;

create or replace function public.claim_my_booking_request(
  p_request_reference text
)
returns table (
  booking_request_id uuid,
  request_reference text,
  booking_status text,
  listing_id uuid,
  agent_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_booking public.booking_requests%rowtype;
  v_profile_phone text;
  v_profile_email text;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if nullif(btrim(coalesce(p_request_reference, '')), '') is null then
    raise exception 'request_reference is required' using errcode = '22023';
  end if;

  select p.*
  into v_profile
  from public.profiles p
  where p.id = v_user_id;

  if v_profile.id is null then
    raise exception 'Customer profile was not found' using errcode = '23503';
  end if;

  v_profile_phone := public.normalize_contact_phone(v_profile.phone_number);
  v_profile_email := public.normalize_contact_email(
    coalesce(v_profile.account_email, auth.jwt() ->> 'email')
  );

  select br.*
  into v_booking
  from public.booking_requests br
  where upper(br.request_reference) = upper(btrim(p_request_reference))
  for update;

  if v_booking.id is null then
    raise exception 'Request could not be claimed' using errcode = 'P0002';
  end if;

  if v_booking.customer_id = v_user_id then
    return query
    select
      v_booking.id,
      v_booking.request_reference,
      v_booking.booking_status::text,
      v_booking.listing_id,
      v_booking.agent_id;
    return;
  end if;

  if v_booking.customer_id is not null
     or not (
       (
         v_profile_phone is not null
         and v_profile_phone = v_booking.customer_phone_normalized
       )
       or (
         v_profile_email is not null
         and v_profile_email = v_booking.customer_email_normalized
       )
     )
  then
    raise exception 'Request could not be claimed' using errcode = '42501';
  end if;

  update public.booking_requests br
  set customer_id = v_user_id
  where br.id = v_booking.id;

  insert into public.audit_logs (
    actor_id,
    action,
    target_table,
    target_id,
    metadata
  )
  values (
    v_user_id,
    'guest_booking_claimed',
    'booking_requests',
    v_booking.id,
    jsonb_build_object('requestReference', v_booking.request_reference)
  );

  return query
  select
    v_booking.id,
    v_booking.request_reference,
    v_booking.booking_status::text,
    v_booking.listing_id,
    v_booking.agent_id;
end;
$$;

create or replace function public.get_my_customer_booking_requests()
returns table (
  booking_request_id uuid,
  request_reference text,
  booking_status text,
  listing_id uuid,
  listing_title text,
  agent_id uuid,
  agent_display_name text,
  agent_business_name text,
  requested_start_at timestamptz,
  requested_end_at timestamptz,
  guest_count integer,
  request_message text,
  requested_service_codes jsonb,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  return query
  select
    br.id,
    br.request_reference,
    br.booking_status::text,
    br.listing_id,
    l.title,
    br.agent_id,
    a.display_name,
    a.business_name,
    br.requested_start_at,
    br.requested_end_at,
    br.guest_count,
    br.request_message,
    br.requested_service_codes,
    br.created_at,
    br.updated_at
  from public.booking_requests br
  join public.listings l on l.id = br.listing_id
  join public.agents a on a.id = br.agent_id
  where br.customer_id = auth.uid()
  order by br.created_at desc, br.id;
end;
$$;

revoke all on function public.is_booking_participant(uuid, uuid)
from public, anon, authenticated;
revoke all on function public.is_booking_assigned_agent(uuid, uuid)
from public, anon, authenticated;
revoke all on function public.create_authenticated_booking_request(
  uuid, text, text, text, timestamptz, timestamptz, integer, text, jsonb
)
from public, anon, authenticated;
revoke all on function public.claim_my_booking_request(text)
from public, anon, authenticated;
revoke all on function public.get_my_customer_booking_requests()
from public, anon, authenticated;

grant execute on function public.is_booking_participant(uuid, uuid)
to authenticated, service_role;
grant execute on function public.is_booking_assigned_agent(uuid, uuid)
to anon, authenticated, service_role;
grant execute on function public.create_authenticated_booking_request(
  uuid, text, text, text, timestamptz, timestamptz, integer, text, jsonb
)
to authenticated, service_role;
grant execute on function public.claim_my_booking_request(text)
to authenticated, service_role;
grant execute on function public.get_my_customer_booking_requests()
to authenticated, service_role;

-- Saved listings and synchronized recently-viewed history.

create table if not exists public.customer_saved_listings (
  customer_id uuid not null references public.profiles (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (customer_id, listing_id)
);

create table if not exists public.customer_listing_views (
  customer_id uuid not null references public.profiles (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  last_viewed_at timestamptz not null default timezone('utc', now()),
  view_count integer not null default 1 check (view_count > 0),
  primary key (customer_id, listing_id)
);

create index if not exists idx_customer_saved_listings_recent
  on public.customer_saved_listings (customer_id, created_at desc);

create index if not exists idx_customer_listing_views_recent
  on public.customer_listing_views (customer_id, last_viewed_at desc);

alter table public.customer_saved_listings enable row level security;
alter table public.customer_listing_views enable row level security;

drop policy if exists "customer_saved_listings_self_select"
on public.customer_saved_listings;
create policy "customer_saved_listings_self_select"
on public.customer_saved_listings
for select
using (customer_id = auth.uid());

drop policy if exists "customer_saved_listings_self_insert"
on public.customer_saved_listings;
create policy "customer_saved_listings_self_insert"
on public.customer_saved_listings
for insert
with check (
  customer_id = auth.uid()
  and public.is_listing_public(listing_id)
);

drop policy if exists "customer_saved_listings_self_delete"
on public.customer_saved_listings;
create policy "customer_saved_listings_self_delete"
on public.customer_saved_listings
for delete
using (customer_id = auth.uid());

drop policy if exists "customer_listing_views_self_select"
on public.customer_listing_views;
create policy "customer_listing_views_self_select"
on public.customer_listing_views
for select
using (customer_id = auth.uid());

drop policy if exists "customer_listing_views_self_insert"
on public.customer_listing_views;
create policy "customer_listing_views_self_insert"
on public.customer_listing_views
for insert
with check (
  customer_id = auth.uid()
  and public.is_listing_public(listing_id)
);

drop policy if exists "customer_listing_views_self_update"
on public.customer_listing_views;
create policy "customer_listing_views_self_update"
on public.customer_listing_views
for update
using (customer_id = auth.uid())
with check (
  customer_id = auth.uid()
  and public.is_listing_public(listing_id)
);

drop policy if exists "customer_listing_views_self_delete"
on public.customer_listing_views;
create policy "customer_listing_views_self_delete"
on public.customer_listing_views
for delete
using (customer_id = auth.uid());

create or replace function public.set_listing_saved(
  p_listing_id uuid,
  p_saved boolean default true
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if coalesce(p_saved, true) then
    if not public.is_listing_public(p_listing_id) then
      raise exception 'Listing is not available' using errcode = 'P0002';
    end if;

    insert into public.customer_saved_listings (customer_id, listing_id)
    values (v_user_id, p_listing_id)
    on conflict (customer_id, listing_id) do nothing;
    return true;
  end if;

  delete from public.customer_saved_listings
  where customer_id = v_user_id
    and listing_id = p_listing_id;
  return false;
end;
$$;

create or replace function public.record_listing_view(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if not public.is_listing_public(p_listing_id) then
    raise exception 'Listing is not available' using errcode = 'P0002';
  end if;

  insert into public.customer_listing_views (
    customer_id,
    listing_id,
    last_viewed_at,
    view_count
  )
  values (
    v_user_id,
    p_listing_id,
    timezone('utc', now()),
    1
  )
  on conflict (customer_id, listing_id) do update
  set
    last_viewed_at = excluded.last_viewed_at,
    view_count = public.customer_listing_views.view_count + 1;
end;
$$;

revoke all on function public.set_listing_saved(uuid, boolean)
from public, anon, authenticated;
revoke all on function public.record_listing_view(uuid)
from public, anon, authenticated;
grant execute on function public.set_listing_saved(uuid, boolean)
to authenticated, service_role;
grant execute on function public.record_listing_view(uuid)
to authenticated, service_role;

-- One private conversation per booking request. Ownership is always copied
-- from booking_requests so a client cannot choose a different agent/customer.

create table if not exists public.booking_conversations (
  id uuid primary key default gen_random_uuid(),
  booking_request_id uuid not null unique
    references public.booking_requests (id) on delete cascade,
  customer_id uuid not null references public.profiles (id) on delete cascade,
  agent_id uuid not null references public.agents (id) on delete cascade,
  status text not null default 'active'
    check (status in ('active', 'closed')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.booking_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null
    references public.booking_conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete restrict,
  message_type text not null default 'text'
    check (message_type in ('text', 'system')),
  body text not null check (char_length(body) between 1 and 4000),
  client_message_id uuid not null default gen_random_uuid(),
  read_at timestamptz,
  edited_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  unique (conversation_id, sender_id, client_message_id)
);

create index if not exists idx_booking_conversations_customer_recent
  on public.booking_conversations (customer_id, updated_at desc);

create index if not exists idx_booking_conversations_agent_recent
  on public.booking_conversations (agent_id, updated_at desc);

create index if not exists idx_booking_messages_conversation_recent
  on public.booking_messages (conversation_id, created_at desc);

create index if not exists idx_booking_messages_unread
  on public.booking_messages (conversation_id, created_at)
  where read_at is null;

create or replace function public.prepare_booking_conversation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.booking_requests%rowtype;
begin
  select br.*
  into v_booking
  from public.booking_requests br
  where br.id = new.booking_request_id;

  if v_booking.id is null then
    raise exception 'Booking request was not found' using errcode = '23503';
  end if;

  if v_booking.customer_id is null then
    raise exception 'A customer account must be linked before chat can start';
  end if;

  if tg_op = 'UPDATE'
     and new.booking_request_id is distinct from old.booking_request_id then
    raise exception 'Conversation booking cannot be changed';
  end if;

  new.customer_id := v_booking.customer_id;
  new.agent_id := v_booking.agent_id;
  return new;
end;
$$;

create or replace function public.guard_booking_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conversation public.booking_conversations%rowtype;
  v_agent_profile_id uuid;
begin
  if tg_op = 'UPDATE'
     and new.conversation_id is not distinct from old.conversation_id
     and new.sender_id is not distinct from old.sender_id
     and new.message_type is not distinct from old.message_type
     and new.body is not distinct from old.body
     and new.client_message_id is not distinct from old.client_message_id
     and new.edited_at is not distinct from old.edited_at
     and new.created_at is not distinct from old.created_at
  then
    return new;
  end if;

  if tg_op <> 'INSERT' then
    raise exception 'Messages are append-only';
  end if;

  select c.*
  into v_conversation
  from public.booking_conversations c
  where c.id = new.conversation_id;

  if v_conversation.id is null or v_conversation.status <> 'active' then
    raise exception 'Conversation is not active';
  end if;

  select a.profile_id
  into v_agent_profile_id
  from public.agents a
  where a.id = v_conversation.agent_id;

  if new.sender_id not in (v_conversation.customer_id, v_agent_profile_id) then
    raise exception 'Message sender is not a conversation participant';
  end if;

  new.body := nullif(btrim(new.body), '');
  if new.body is null or char_length(new.body) > 4000 then
    raise exception 'Message must contain between 1 and 4000 characters';
  end if;

  if new.message_type is distinct from 'system'
     and new.sender_id is distinct from auth.uid() then
    raise exception 'Message sender must match the authenticated user';
  end if;

  return new;
end;
$$;

create or replace function public.touch_conversation_after_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.booking_conversations
  set updated_at = new.created_at
  where id = new.conversation_id;
  return new;
end;
$$;

create or replace function public.notify_booking_message_recipient()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conversation public.booking_conversations%rowtype;
  v_agent_profile_id uuid;
  v_recipient_id uuid;
begin
  select c.*
  into v_conversation
  from public.booking_conversations c
  where c.id = new.conversation_id;

  select a.profile_id
  into v_agent_profile_id
  from public.agents a
  where a.id = v_conversation.agent_id;

  v_recipient_id := case
    when new.sender_id = v_conversation.customer_id then v_agent_profile_id
    else v_conversation.customer_id
  end;

  if v_recipient_id is not null then
    insert into public.notifications (
      user_id,
      booking_request_id,
      type,
      title,
      body,
      payload
    )
    values (
      v_recipient_id,
      v_conversation.booking_request_id,
      'message_received'::public.notification_type,
      'New message',
      left(new.body, 140),
      jsonb_build_object(
        'eventType', 'message_received',
        'bookingId', v_conversation.booking_request_id,
        'conversationId', v_conversation.id,
        'messageId', new.id
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists prepare_booking_conversation
on public.booking_conversations;
create trigger prepare_booking_conversation
before insert or update on public.booking_conversations
for each row execute function public.prepare_booking_conversation();

drop trigger if exists set_booking_conversations_updated_at
on public.booking_conversations;
create trigger set_booking_conversations_updated_at
before update on public.booking_conversations
for each row execute function public.set_updated_at();

drop trigger if exists guard_booking_message on public.booking_messages;
create trigger guard_booking_message
before insert or update or delete on public.booking_messages
for each row execute function public.guard_booking_message();

drop trigger if exists touch_conversation_after_message
on public.booking_messages;
create trigger touch_conversation_after_message
after insert on public.booking_messages
for each row execute function public.touch_conversation_after_message();

drop trigger if exists notify_booking_message_recipient
on public.booking_messages;
create trigger notify_booking_message_recipient
after insert on public.booking_messages
for each row execute function public.notify_booking_message_recipient();

alter table public.booking_conversations enable row level security;
alter table public.booking_messages enable row level security;

drop policy if exists "booking_conversations_participant_admin_select"
on public.booking_conversations;
create policy "booking_conversations_participant_admin_select"
on public.booking_conversations
for select
using (
  public.is_admin()
  or public.is_booking_participant(booking_request_id)
);

drop policy if exists "booking_messages_participant_admin_select"
on public.booking_messages;
create policy "booking_messages_participant_admin_select"
on public.booking_messages
for select
using (
  public.is_admin()
  or exists (
    select 1
    from public.booking_conversations c
    where c.id = booking_messages.conversation_id
      and public.is_booking_participant(c.booking_request_id)
  )
);

create or replace function public.get_or_create_booking_conversation(
  p_booking_request_id uuid
)
returns setof public.booking_conversations
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if not (
    public.is_admin(auth.uid())
    or public.is_booking_participant(p_booking_request_id, auth.uid())
  ) then
    raise exception 'Booking conversation is not available' using errcode = '42501';
  end if;

  insert into public.booking_conversations (
    booking_request_id,
    customer_id,
    agent_id
  )
  select br.id, br.customer_id, br.agent_id
  from public.booking_requests br
  where br.id = p_booking_request_id
    and br.customer_id is not null
  on conflict (booking_request_id) do nothing;

  if not found and not exists (
    select 1
    from public.booking_conversations c
    where c.booking_request_id = p_booking_request_id
  ) then
    raise exception 'A linked customer is required before chat can start';
  end if;

  return query
  select c.*
  from public.booking_conversations c
  where c.booking_request_id = p_booking_request_id;
end;
$$;

create or replace function public.send_booking_message(
  p_conversation_id uuid,
  p_body text,
  p_client_message_id uuid default gen_random_uuid()
)
returns setof public.booking_messages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_conversation public.booking_conversations%rowtype;
  v_message_id uuid;
  v_client_message_id uuid := coalesce(p_client_message_id, gen_random_uuid());
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  select c.*
  into v_conversation
  from public.booking_conversations c
  where c.id = p_conversation_id;

  if v_conversation.id is null
     or v_conversation.status <> 'active'
     or not public.is_booking_participant(
       v_conversation.booking_request_id,
       v_user_id
     )
  then
    raise exception 'Conversation is not available' using errcode = '42501';
  end if;

  if nullif(btrim(coalesce(p_body, '')), '') is null
     or char_length(btrim(p_body)) > 4000 then
    raise exception 'Message must contain between 1 and 4000 characters'
      using errcode = '22023';
  end if;

  insert into public.booking_messages (
    conversation_id,
    sender_id,
    message_type,
    body,
    client_message_id
  )
  values (
    p_conversation_id,
    v_user_id,
    'text',
    btrim(p_body),
    v_client_message_id
  )
  on conflict (conversation_id, sender_id, client_message_id) do nothing
  returning id into v_message_id;

  if v_message_id is null then
    select m.id
    into v_message_id
    from public.booking_messages m
    where m.conversation_id = p_conversation_id
      and m.sender_id = v_user_id
      and m.client_message_id = v_client_message_id;
  end if;

  return query
  select m.*
  from public.booking_messages m
  where m.id = v_message_id;
end;
$$;

create or replace function public.mark_conversation_read(
  p_conversation_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_booking_request_id uuid;
  v_updated integer;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  select c.booking_request_id
  into v_booking_request_id
  from public.booking_conversations c
  where c.id = p_conversation_id;

  if v_booking_request_id is null
     or not public.is_booking_participant(v_booking_request_id, v_user_id) then
    raise exception 'Conversation is not available' using errcode = '42501';
  end if;

  update public.booking_messages m
  set read_at = timezone('utc', now())
  where m.conversation_id = p_conversation_id
    and m.sender_id <> v_user_id
    and m.read_at is null;

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

create or replace function public.set_booking_conversation_status(
  p_conversation_id uuid,
  p_status text
)
returns setof public.booking_conversations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking_request_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if p_status not in ('active', 'closed') then
    raise exception 'Conversation status is invalid' using errcode = '22023';
  end if;

  select c.booking_request_id
  into v_booking_request_id
  from public.booking_conversations c
  where c.id = p_conversation_id;

  if v_booking_request_id is null
     or not (
       public.is_admin(auth.uid())
       or public.is_booking_participant(v_booking_request_id, auth.uid())
     )
  then
    raise exception 'Conversation is not available' using errcode = '42501';
  end if;

  update public.booking_conversations c
  set status = p_status
  where c.id = p_conversation_id;

  return query
  select c.*
  from public.booking_conversations c
  where c.id = p_conversation_id;
end;
$$;

revoke all on function public.get_or_create_booking_conversation(uuid)
from public, anon, authenticated;
revoke all on function public.send_booking_message(uuid, text, uuid)
from public, anon, authenticated;
revoke all on function public.mark_conversation_read(uuid)
from public, anon, authenticated;
revoke all on function public.set_booking_conversation_status(uuid, text)
from public, anon, authenticated;

grant execute on function public.get_or_create_booking_conversation(uuid)
to authenticated, service_role;
grant execute on function public.send_booking_message(uuid, text, uuid)
to authenticated, service_role;
grant execute on function public.mark_conversation_read(uuid)
to authenticated, service_role;
grant execute on function public.set_booking_conversation_status(uuid, text)
to authenticated, service_role;

-- Viewing appointments are attached to the same request and participants as
-- chat. No appointment operation changes booking_status implicitly.

create table if not exists public.viewing_appointments (
  id uuid primary key default gen_random_uuid(),
  booking_request_id uuid not null
    references public.booking_requests (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  customer_id uuid not null references public.profiles (id) on delete cascade,
  agent_id uuid not null references public.agents (id) on delete cascade,
  proposed_by uuid not null references public.profiles (id) on delete restrict,
  scheduled_start_at timestamptz not null,
  scheduled_end_at timestamptz not null,
  status text not null default 'proposed'
    check (status in (
      'proposed',
      'confirmed',
      'reschedule_requested',
      'completed',
      'cancelled',
      'no_show'
    )),
  location_note text,
  response_note text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (scheduled_end_at > scheduled_start_at)
);

create index if not exists idx_viewing_appointments_booking_recent
  on public.viewing_appointments (booking_request_id, created_at desc);

create index if not exists idx_viewing_appointments_agent_schedule
  on public.viewing_appointments (agent_id, scheduled_start_at)
  where status in ('proposed', 'confirmed', 'reschedule_requested');

create index if not exists idx_viewing_appointments_customer_schedule
  on public.viewing_appointments (customer_id, scheduled_start_at)
  where status in ('proposed', 'confirmed', 'reschedule_requested');

create or replace function public.prepare_viewing_appointment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.booking_requests%rowtype;
  v_agent_profile_id uuid;
begin
  select br.*
  into v_booking
  from public.booking_requests br
  where br.id = new.booking_request_id;

  if v_booking.id is null then
    raise exception 'Booking request was not found' using errcode = '23503';
  end if;

  if v_booking.customer_id is null then
    raise exception 'A customer account must be linked before scheduling';
  end if;

  select a.profile_id
  into v_agent_profile_id
  from public.agents a
  where a.id = v_booking.agent_id;

  if new.proposed_by not in (v_booking.customer_id, v_agent_profile_id) then
    raise exception 'Appointment proposer is not a booking participant';
  end if;

  if new.scheduled_end_at <= new.scheduled_start_at then
    raise exception 'Appointment end must be after its start';
  end if;

  if char_length(coalesce(new.location_note, '')) > 500
     or char_length(coalesce(new.response_note, '')) > 500 then
    raise exception 'Appointment notes must not exceed 500 characters';
  end if;

  if tg_op = 'UPDATE' then
    if new.booking_request_id is distinct from old.booking_request_id
       or new.listing_id is distinct from old.listing_id
       or new.customer_id is distinct from old.customer_id
       or new.agent_id is distinct from old.agent_id
       or new.created_at is distinct from old.created_at then
      raise exception 'Appointment ownership fields cannot be changed';
    end if;

    if old.status in ('completed', 'cancelled', 'no_show')
       and not public.is_admin(auth.uid()) then
      raise exception 'A final appointment cannot be changed';
    end if;
  else
    new.status := 'proposed';
  end if;

  new.listing_id := v_booking.listing_id;
  new.customer_id := v_booking.customer_id;
  new.agent_id := v_booking.agent_id;
  new.location_note := nullif(btrim(new.location_note), '');
  new.response_note := nullif(btrim(new.response_note), '');
  return new;
end;
$$;

create or replace function public.notify_viewing_appointment_participant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agent_profile_id uuid;
  v_actor_id uuid := auth.uid();
  v_recipient_id uuid;
  v_event_action text;
begin
  select a.profile_id
  into v_agent_profile_id
  from public.agents a
  where a.id = new.agent_id;

  v_recipient_id := case
    when v_actor_id = new.customer_id then v_agent_profile_id
    when v_actor_id = v_agent_profile_id then new.customer_id
    when new.proposed_by = new.customer_id then v_agent_profile_id
    else new.customer_id
  end;

  v_event_action := case
    when tg_op = 'INSERT' then 'viewing_proposed'
    else 'viewing_' || new.status
  end;

  if v_recipient_id is not null then
    insert into public.notifications (
      user_id,
      booking_request_id,
      type,
      title,
      body,
      payload
    )
    values (
      v_recipient_id,
      new.booking_request_id,
      'viewing_updated'::public.notification_type,
      case when tg_op = 'INSERT' then 'Viewing proposed' else 'Viewing updated' end,
      'Viewing status: ' || new.status,
      jsonb_build_object(
        'eventType', v_event_action,
        'bookingId', new.booking_request_id,
        'appointmentId', new.id,
        'status', new.status,
        'scheduledStartAt', new.scheduled_start_at,
        'scheduledEndAt', new.scheduled_end_at
      )
    );
  end if;

  insert into public.audit_logs (
    actor_id,
    action,
    target_table,
    target_id,
    metadata
  )
  values (
    v_actor_id,
    v_event_action,
    'viewing_appointments',
    new.id,
    jsonb_build_object(
      'bookingId', new.booking_request_id,
      'status', new.status
    )
  );

  return new;
end;
$$;

drop trigger if exists prepare_viewing_appointment
on public.viewing_appointments;
create trigger prepare_viewing_appointment
before insert or update on public.viewing_appointments
for each row execute function public.prepare_viewing_appointment();

drop trigger if exists set_viewing_appointments_updated_at
on public.viewing_appointments;
create trigger set_viewing_appointments_updated_at
before update on public.viewing_appointments
for each row execute function public.set_updated_at();

drop trigger if exists notify_viewing_appointment_participant
on public.viewing_appointments;
create trigger notify_viewing_appointment_participant
after insert or update of status, scheduled_start_at, scheduled_end_at
on public.viewing_appointments
for each row execute function public.notify_viewing_appointment_participant();

alter table public.viewing_appointments enable row level security;

drop policy if exists "viewing_appointments_participant_admin_select"
on public.viewing_appointments;
create policy "viewing_appointments_participant_admin_select"
on public.viewing_appointments
for select
using (
  public.is_admin()
  or public.is_booking_participant(booking_request_id)
);

create or replace function public.propose_viewing_appointment(
  p_booking_request_id uuid,
  p_scheduled_start_at timestamptz,
  p_scheduled_end_at timestamptz,
  p_location_note text default null
)
returns setof public.viewing_appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_appointment_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if not public.is_booking_participant(p_booking_request_id, v_user_id) then
    raise exception 'Booking is not available' using errcode = '42501';
  end if;

  if p_scheduled_start_at <= timezone('utc', now())
     or p_scheduled_end_at <= p_scheduled_start_at then
    raise exception 'Choose a valid future viewing time' using errcode = '22023';
  end if;

  insert into public.viewing_appointments (
    booking_request_id,
    listing_id,
    customer_id,
    agent_id,
    proposed_by,
    scheduled_start_at,
    scheduled_end_at,
    location_note
  )
  select
    br.id,
    br.listing_id,
    br.customer_id,
    br.agent_id,
    v_user_id,
    p_scheduled_start_at,
    p_scheduled_end_at,
    p_location_note
  from public.booking_requests br
  where br.id = p_booking_request_id
    and br.customer_id is not null
  returning id into v_appointment_id;

  if v_appointment_id is null then
    raise exception 'A linked customer is required before scheduling';
  end if;

  return query
  select va.*
  from public.viewing_appointments va
  where va.id = v_appointment_id;
end;
$$;

create or replace function public.respond_to_viewing_appointment(
  p_appointment_id uuid,
  p_status text,
  p_scheduled_start_at timestamptz default null,
  p_scheduled_end_at timestamptz default null,
  p_response_note text default null
)
returns setof public.viewing_appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_appointment public.viewing_appointments%rowtype;
  v_is_admin boolean;
  v_is_agent boolean;
  v_start timestamptz;
  v_end timestamptz;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if p_status not in (
    'confirmed',
    'reschedule_requested',
    'completed',
    'cancelled',
    'no_show'
  ) then
    raise exception 'Appointment response status is invalid'
      using errcode = '22023';
  end if;

  select va.*
  into v_appointment
  from public.viewing_appointments va
  where va.id = p_appointment_id
  for update;

  v_is_admin := public.is_admin(v_user_id);
  v_is_agent := public.is_booking_assigned_agent(
    v_appointment.booking_request_id,
    v_user_id
  );

  if v_appointment.id is null
     or not (
       v_is_admin
       or public.is_booking_participant(
         v_appointment.booking_request_id,
         v_user_id
       )
     )
  then
    raise exception 'Appointment is not available' using errcode = '42501';
  end if;

  if v_appointment.status in ('completed', 'cancelled', 'no_show')
     and not v_is_admin then
    raise exception 'A final appointment cannot be changed';
  end if;

  if p_status = 'confirmed'
     and v_appointment.proposed_by = v_user_id
     and not v_is_admin then
    raise exception 'The other participant must confirm this proposal';
  end if;

  if p_status in ('completed', 'no_show')
     and not (v_is_agent or v_is_admin) then
    raise exception 'Only the assigned agent can set this status'
      using errcode = '42501';
  end if;

  if p_status = 'reschedule_requested' then
    if p_scheduled_start_at is null or p_scheduled_end_at is null then
      raise exception 'A new start and end time are required for rescheduling';
    end if;
    v_start := p_scheduled_start_at;
    v_end := p_scheduled_end_at;
  else
    v_start := v_appointment.scheduled_start_at;
    v_end := v_appointment.scheduled_end_at;
  end if;

  if v_end <= v_start
     or (
       p_status in ('confirmed', 'reschedule_requested')
       and v_start <= timezone('utc', now())
     ) then
    raise exception 'Choose a valid future viewing time' using errcode = '22023';
  end if;

  update public.viewing_appointments va
  set
    status = p_status,
    scheduled_start_at = v_start,
    scheduled_end_at = v_end,
    proposed_by = case
      when p_status = 'reschedule_requested' then v_user_id
      else va.proposed_by
    end,
    response_note = nullif(btrim(p_response_note), '')
  where va.id = p_appointment_id;

  return query
  select va.*
  from public.viewing_appointments va
  where va.id = p_appointment_id;
end;
$$;

revoke all on function public.propose_viewing_appointment(
  uuid, timestamptz, timestamptz, text
)
from public, anon, authenticated;
revoke all on function public.respond_to_viewing_appointment(
  uuid, text, timestamptz, timestamptz, text
)
from public, anon, authenticated;

grant execute on function public.propose_viewing_appointment(
  uuid, timestamptz, timestamptz, text
)
to authenticated, service_role;
grant execute on function public.respond_to_viewing_appointment(
  uuid, text, timestamptz, timestamptz, text
)
to authenticated, service_role;

-- Existing reviews become verified transaction reviews. Historical rows are
-- preserved but are public only when their booking can be verified completed.

-- Some early production projects were provisioned before the reviews table
-- from the repository baseline. Create the compatible base table so this
-- forward migration also repairs those projects.
create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  booking_request_id uuid not null unique
    references public.booking_requests (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  customer_id uuid not null references public.profiles (id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default timezone('utc', now())
);

alter table public.reviews enable row level security;

alter table public.reviews
  add column if not exists agent_id uuid references public.agents (id) on delete cascade,
  add column if not exists is_verified boolean,
  add column if not exists moderation_status text,
  add column if not exists updated_at timestamptz;

drop trigger if exists prepare_verified_review on public.reviews;

update public.reviews r
set
  listing_id = br.listing_id,
  agent_id = br.agent_id,
  is_verified = (
    br.booking_status = 'completed'::public.booking_status
    and br.customer_id = r.customer_id
  ),
  moderation_status = case
    when br.booking_status = 'completed'::public.booking_status
      and br.customer_id = r.customer_id then 'visible'
    else 'pending'
  end,
  updated_at = coalesce(r.updated_at, r.created_at, timezone('utc', now()))
from public.booking_requests br
where br.id = r.booking_request_id;

alter table public.reviews
  alter column agent_id set not null,
  alter column is_verified set default false,
  alter column is_verified set not null,
  alter column moderation_status set default 'visible',
  alter column moderation_status set not null,
  alter column updated_at set default timezone('utc', now()),
  alter column updated_at set not null;

alter table public.reviews
  drop constraint if exists reviews_moderation_status_check;

alter table public.reviews
  add constraint reviews_moderation_status_check
  check (moderation_status in ('visible', 'hidden', 'pending'));

create index if not exists idx_reviews_agent_verified_recent
  on public.reviews (agent_id, is_verified, moderation_status, created_at desc);

create or replace function public.prepare_verified_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.booking_requests%rowtype;
begin
  if tg_op = 'UPDATE' then
    if public.is_admin(auth.uid()) then
      if new.booking_request_id is distinct from old.booking_request_id
         or new.listing_id is distinct from old.listing_id
         or new.agent_id is distinct from old.agent_id
         or new.customer_id is distinct from old.customer_id
         or new.rating is distinct from old.rating
         or new.comment is distinct from old.comment
         or new.is_verified is distinct from old.is_verified
         or new.created_at is distinct from old.created_at then
        raise exception 'Admin can update only review moderation fields';
      end if;
      return new;
    end if;

    raise exception 'Reviews cannot be edited directly';
  end if;

  select br.*
  into v_booking
  from public.booking_requests br
  where br.id = new.booking_request_id;

  if auth.uid() is null
     or v_booking.id is null
     or v_booking.customer_id is distinct from auth.uid()
     or v_booking.booking_status <> 'completed'::public.booking_status then
    raise exception 'Only the linked customer can review a completed booking'
      using errcode = '42501';
  end if;

  new.customer_id := auth.uid();
  new.listing_id := v_booking.listing_id;
  new.agent_id := v_booking.agent_id;
  new.is_verified := true;
  new.moderation_status := 'visible';
  new.comment := nullif(btrim(new.comment), '');

  if char_length(coalesce(new.comment, '')) > 2000 then
    raise exception 'Review comment must not exceed 2000 characters';
  end if;

  return new;
end;
$$;

create or replace function public.notify_agent_of_verified_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agent_profile_id uuid;
begin
  select a.profile_id
  into v_agent_profile_id
  from public.agents a
  where a.id = new.agent_id;

  if v_agent_profile_id is not null then
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
      new.booking_request_id,
      'review_received'::public.notification_type,
      'New verified review',
      'A customer left a ' || new.rating::text || '-star review.',
      jsonb_build_object(
        'eventType', 'review_received',
        'bookingId', new.booking_request_id,
        'reviewId', new.id,
        'rating', new.rating
      )
    );
  end if;

  insert into public.audit_logs (
    actor_id,
    action,
    target_table,
    target_id,
    metadata
  )
  values (
    new.customer_id,
    'verified_review_submitted',
    'reviews',
    new.id,
    jsonb_build_object(
      'bookingId', new.booking_request_id,
      'agentId', new.agent_id,
      'rating', new.rating
    )
  );

  return new;
end;
$$;

drop trigger if exists prepare_verified_review on public.reviews;
create trigger prepare_verified_review
before insert or update on public.reviews
for each row execute function public.prepare_verified_review();

drop trigger if exists set_reviews_updated_at on public.reviews;
create trigger set_reviews_updated_at
before update on public.reviews
for each row execute function public.set_updated_at();

drop trigger if exists notify_agent_of_verified_review on public.reviews;
create trigger notify_agent_of_verified_review
after insert on public.reviews
for each row execute function public.notify_agent_of_verified_review();

drop policy if exists "reviews_public_select" on public.reviews;
drop policy if exists "reviews_customer_insert" on public.reviews;
drop policy if exists "reviews_verified_public_participant_admin_select"
on public.reviews;
drop policy if exists "reviews_admin_moderate"
on public.reviews;

create policy "reviews_verified_public_participant_admin_select"
on public.reviews
for select
using (
  (is_verified and moderation_status = 'visible')
  or customer_id = auth.uid()
  or public.is_admin()
  or public.is_booking_assigned_agent(booking_request_id)
);

create policy "reviews_admin_moderate"
on public.reviews
for update
using (public.is_admin())
with check (public.is_admin());

create or replace function public.submit_verified_review(
  p_booking_request_id uuid,
  p_rating integer,
  p_comment text default null
)
returns setof public.reviews
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_review_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if p_rating < 1 or p_rating > 5 then
    raise exception 'Rating must be between 1 and 5' using errcode = '22023';
  end if;

  insert into public.reviews (
    booking_request_id,
    listing_id,
    agent_id,
    customer_id,
    rating,
    comment,
    is_verified,
    moderation_status
  )
  select
    br.id,
    br.listing_id,
    br.agent_id,
    v_user_id,
    p_rating,
    p_comment,
    true,
    'visible'
  from public.booking_requests br
  where br.id = p_booking_request_id
    and br.customer_id = v_user_id
    and br.booking_status = 'completed'::public.booking_status
  returning id into v_review_id;

  if v_review_id is null then
    raise exception 'Only a completed linked booking can be reviewed'
      using errcode = '42501';
  end if;

  return query
  select r.*
  from public.reviews r
  where r.id = v_review_id;
exception
  when unique_violation then
    raise exception 'This booking has already been reviewed'
      using errcode = '23505';
end;
$$;

revoke all on function public.submit_verified_review(uuid, integer, text)
from public, anon, authenticated;
grant execute on function public.submit_verified_review(uuid, integer, text)
to authenticated, service_role;

-- Notifications remain the realtime inbox. Delivery fields provide a safe
-- retry queue for a future FCM/APNs worker without changing current clients.

alter table public.notifications
  add column if not exists delivery_status text,
  add column if not exists delivery_attempts integer not null default 0,
  add column if not exists next_delivery_attempt_at timestamptz,
  add column if not exists last_delivery_attempt_at timestamptz,
  add column if not exists delivered_at timestamptz,
  add column if not exists delivery_error text;

-- Legacy projects can have a restrictive notification-update trigger with a
-- different historical name. Disable user triggers only for this data repair;
-- the migration installs the current guard immediately below.
alter table public.notifications disable trigger user;
update public.notifications
set delivery_status = 'skipped'
where delivery_status is null;
alter table public.notifications enable trigger user;

alter table public.notifications
  alter column delivery_status set default 'queued',
  alter column delivery_status set not null;

alter table public.notifications
  drop constraint if exists notifications_delivery_status_check,
  drop constraint if exists notifications_delivery_attempts_check;

alter table public.notifications
  add constraint notifications_delivery_status_check
  check (delivery_status in (
    'queued', 'processing', 'sent', 'failed', 'skipped'
  )),
  add constraint notifications_delivery_attempts_check
  check (delivery_attempts >= 0);

create index if not exists idx_notifications_delivery_queue
  on public.notifications (
    delivery_status,
    next_delivery_attempt_at,
    created_at
  )
  where delivery_status in ('queued', 'failed');

create or replace function public.guard_notification_update()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_jwt_role text := coalesce(auth.jwt() ->> 'role', '');
begin
  if public.is_admin(auth.uid())
     or v_jwt_role = 'service_role'
     or (auth.uid() is null and session_user in ('postgres', 'supabase_admin')) then
    return new;
  end if;

  if old.user_id <> auth.uid() then
    raise exception 'Notification is not available' using errcode = '42501';
  end if;

  if new.id is distinct from old.id
     or new.user_id is distinct from old.user_id
     or new.booking_request_id is distinct from old.booking_request_id
     or new.type is distinct from old.type
     or new.title is distinct from old.title
     or new.body is distinct from old.body
     or new.payload is distinct from old.payload
     or new.created_at is distinct from old.created_at
     or new.delivery_status is distinct from old.delivery_status
     or new.delivery_attempts is distinct from old.delivery_attempts
     or new.next_delivery_attempt_at is distinct from old.next_delivery_attempt_at
     or new.last_delivery_attempt_at is distinct from old.last_delivery_attempt_at
     or new.delivered_at is distinct from old.delivered_at
     or new.delivery_error is distinct from old.delivery_error then
    raise exception 'Customers can update only notification read state';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_notification_update on public.notifications;
create trigger guard_notification_update
before update on public.notifications
for each row execute function public.guard_notification_update();

drop policy if exists "notifications_manage_session_select"
on public.notifications;
drop policy if exists "notifications_manage_session_update"
on public.notifications;
drop policy if exists "notifications_self_select"
on public.notifications;
drop policy if exists "notifications_self_update"
on public.notifications;

create policy "notifications_self_select"
on public.notifications
for select
using (user_id = auth.uid() or public.is_admin());

create policy "notifications_self_update"
on public.notifications
for update
using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

drop policy if exists "device_tokens_manage_session_all"
on public.device_tokens;
drop policy if exists "device_tokens_self_all"
on public.device_tokens;
create policy "device_tokens_self_all"
on public.device_tokens
for all
using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

-- Contact-payment operations remain service-controlled. Admins receive a
-- sanitized RPC instead of direct access to checkout/webhook payloads.

alter table public.listing_contact_payments
  add column if not exists customer_id uuid
    references public.profiles (id) on delete set null,
  add column if not exists webhook_received_at timestamptz,
  add column if not exists reconciliation_status text,
  add column if not exists reconciliation_attempts integer not null default 0,
  add column if not exists last_reconciled_at timestamptz,
  add column if not exists next_reconcile_at timestamptz,
  add column if not exists reconciliation_error text;

update public.listing_contact_payments
set reconciliation_status = case
  when payment_status = 'paid' then 'matched'
  when payment_status in ('failed', 'expired', 'cancelled') then 'not_required'
  else 'pending'
end
where reconciliation_status is null;

alter table public.listing_contact_payments
  alter column reconciliation_status set default 'pending',
  alter column reconciliation_status set not null,
  drop constraint if exists listing_contact_payments_reconciliation_status_check,
  drop constraint if exists listing_contact_payments_reconciliation_attempts_check;

alter table public.listing_contact_payments
  add constraint listing_contact_payments_reconciliation_status_check
  check (reconciliation_status in (
    'pending', 'matched', 'mismatch', 'manual_review', 'reconciled', 'not_required'
  )),
  add constraint listing_contact_payments_reconciliation_attempts_check
  check (reconciliation_attempts >= 0);

create index if not exists idx_listing_contact_payments_reconciliation_queue
  on public.listing_contact_payments (
    reconciliation_status,
    next_reconcile_at,
    created_at
  )
  where reconciliation_status in ('pending', 'mismatch', 'manual_review');

create table if not exists public.payment_provider_events (
  id bigint generated by default as identity primary key,
  payment_id uuid references public.listing_contact_payments (id) on delete set null,
  order_reference text,
  provider_event_id text,
  event_type text not null,
  provider_status text,
  payload jsonb not null default '{}'::jsonb,
  processing_status text not null default 'received'
    check (processing_status in ('received', 'processed', 'ignored', 'failed')),
  processing_error text,
  received_at timestamptz not null default timezone('utc', now()),
  processed_at timestamptz
);

create unique index if not exists idx_payment_provider_events_provider_id
  on public.payment_provider_events (provider_event_id)
  where provider_event_id is not null;

create index if not exists idx_payment_provider_events_payment_recent
  on public.payment_provider_events (payment_id, received_at desc);

alter table public.payment_provider_events enable row level security;

create or replace function public.audit_contact_payment_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.payment_status is distinct from old.payment_status
     or new.reconciliation_status is distinct from old.reconciliation_status then
    insert into public.audit_logs (
      actor_id,
      action,
      target_table,
      target_id,
      metadata
    )
    values (
      auth.uid(),
      'contact_payment_status_changed',
      'listing_contact_payments',
      new.id,
      jsonb_build_object(
        'orderReference', new.order_reference,
        'oldPaymentStatus', old.payment_status,
        'newPaymentStatus', new.payment_status,
        'oldReconciliationStatus', old.reconciliation_status,
        'newReconciliationStatus', new.reconciliation_status
      )
    );
  end if;
  return new;
end;
$$;

create or replace function public.audit_contact_payment_toggle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.contact_payments_enabled is distinct from old.contact_payments_enabled then
    insert into public.audit_logs (
      actor_id,
      action,
      target_table,
      target_id,
      metadata
    )
    values (
      coalesce(auth.uid(), new.updated_by),
      'contact_payment_toggle_changed',
      'marketplace_settings',
      null,
      jsonb_build_object(
        'oldEnabled', old.contact_payments_enabled,
        'newEnabled', new.contact_payments_enabled
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists audit_contact_payment_status_change
on public.listing_contact_payments;
create trigger audit_contact_payment_status_change
after update of payment_status, reconciliation_status
on public.listing_contact_payments
for each row execute function public.audit_contact_payment_status_change();

drop trigger if exists audit_contact_payment_toggle
on public.marketplace_settings;
create trigger audit_contact_payment_toggle
after update of contact_payments_enabled
on public.marketplace_settings
for each row execute function public.audit_contact_payment_toggle();

create or replace function public.get_admin_payment_operations(
  p_payment_status text default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns table (
  payment_id uuid,
  order_reference text,
  listing_id uuid,
  listing_title text,
  agent_id uuid,
  agent_display_name text,
  customer_name text,
  customer_phone_number text,
  customer_email text,
  requested_amount numeric,
  requested_currency text,
  payment_provider text,
  payment_status text,
  provider_payment_reference text,
  provider_channel text,
  status_message text,
  initiated_at timestamptz,
  paid_at timestamptz,
  failed_at timestamptz,
  contact_revealed_at timestamptz,
  webhook_received_at timestamptz,
  reconciliation_status text,
  reconciliation_attempts integer,
  last_reconciled_at timestamptz,
  next_reconcile_at timestamptz,
  reconciliation_error text,
  last_event_type text,
  last_event_status text,
  last_event_received_at timestamptz,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Admin access is required' using errcode = '42501';
  end if;

  return query
  select
    p.id,
    p.order_reference,
    p.listing_id,
    l.title,
    p.agent_id,
    coalesce(a.display_name, a.business_name),
    p.customer_name,
    p.customer_phone_number,
    p.customer_email,
    p.requested_amount,
    p.requested_currency,
    p.payment_provider,
    p.payment_status,
    p.provider_payment_reference,
    p.provider_channel,
    p.status_message,
    p.initiated_at,
    p.paid_at,
    p.failed_at,
    p.contact_revealed_at,
    p.webhook_received_at,
    p.reconciliation_status,
    p.reconciliation_attempts,
    p.last_reconciled_at,
    p.next_reconcile_at,
    p.reconciliation_error,
    pe.event_type,
    pe.processing_status,
    pe.received_at,
    count(*) over ()
  from public.listing_contact_payments p
  join public.listings l on l.id = p.listing_id
  join public.agents a on a.id = p.agent_id
  left join lateral (
    select e.event_type, e.processing_status, e.received_at
    from public.payment_provider_events e
    where e.payment_id = p.id
    order by e.received_at desc, e.id desc
    limit 1
  ) pe on true
  where nullif(btrim(coalesce(p_payment_status, '')), '') is null
     or p.payment_status = lower(btrim(p_payment_status))
  order by p.created_at desc, p.id
  limit least(greatest(coalesce(p_limit, 100), 1), 500)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.get_admin_payment_operations(text, integer, integer)
from public, anon, authenticated;
grant execute on function public.get_admin_payment_operations(text, integer, integer)
to authenticated, service_role;

-- Privacy support for the account UI. This records a request for reviewed,
-- auditable deletion rather than deleting bookings or financial records.

create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'in_review', 'completed', 'rejected')),
  reason text,
  requested_at timestamptz not null default timezone('utc', now()),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles (id) on delete set null,
  resolution_note text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists idx_account_deletion_requests_one_open
  on public.account_deletion_requests (customer_id)
  where status in ('pending', 'in_review');

alter table public.account_deletion_requests enable row level security;

drop policy if exists "account_deletion_requests_self_admin_select"
on public.account_deletion_requests;
create policy "account_deletion_requests_self_admin_select"
on public.account_deletion_requests
for select
using (customer_id = auth.uid() or public.is_admin());

drop policy if exists "account_deletion_requests_admin_update"
on public.account_deletion_requests;
create policy "account_deletion_requests_admin_update"
on public.account_deletion_requests
for update
using (public.is_admin())
with check (public.is_admin());

drop trigger if exists set_account_deletion_requests_updated_at
on public.account_deletion_requests;
create trigger set_account_deletion_requests_updated_at
before update on public.account_deletion_requests
for each row execute function public.set_updated_at();

create or replace function public.request_my_account_deletion(
  p_reason text default null
)
returns setof public.account_deletion_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_request_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if char_length(coalesce(p_reason, '')) > 1000 then
    raise exception 'Deletion reason must not exceed 1000 characters';
  end if;

  select adr.id
  into v_request_id
  from public.account_deletion_requests adr
  where adr.customer_id = v_user_id
    and adr.status in ('pending', 'in_review')
  order by adr.requested_at desc
  limit 1;

  if v_request_id is null then
    insert into public.account_deletion_requests (customer_id, reason)
    values (v_user_id, nullif(btrim(p_reason), ''))
    returning id into v_request_id;

    insert into public.audit_logs (
      actor_id,
      action,
      target_table,
      target_id,
      metadata
    )
    values (
      v_user_id,
      'account_deletion_requested',
      'account_deletion_requests',
      v_request_id,
      '{}'::jsonb
    );
  end if;

  return query
  select adr.*
  from public.account_deletion_requests adr
  where adr.id = v_request_id;
end;
$$;

revoke all on function public.request_my_account_deletion(text)
from public, anon, authenticated;
grant execute on function public.request_my_account_deletion(text)
to authenticated, service_role;

-- Realtime publishes only participant-filtered rows; RLS remains authoritative.
do $$
declare
  v_table text;
begin
  if exists (
    select 1
    from pg_publication p
    where p.pubname = 'supabase_realtime'
      and not p.puballtables
  ) then
    foreach v_table in array array[
      'booking_requests',
      'booking_status_history',
      'booking_conversations',
      'booking_messages',
      'viewing_appointments',
      'notifications'
    ]
    loop
      if not exists (
        select 1
        from pg_publication_tables pt
        where pt.pubname = 'supabase_realtime'
          and pt.schemaname = 'public'
          and pt.tablename = v_table
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          v_table
        );
      end if;
    end loop;
  end if;
end
$$;

-- Explicit API privileges complement RLS and avoid relying on project-wide
-- default privileges.
grant select, insert, delete on public.customer_saved_listings to authenticated;
grant select, insert, update, delete on public.customer_listing_views to authenticated;
grant select on public.booking_conversations to authenticated;
grant select on public.booking_messages to authenticated;
grant select on public.viewing_appointments to authenticated;
grant select on public.account_deletion_requests to authenticated;

revoke insert, update, delete on public.booking_conversations from anon, authenticated;
revoke insert, update, delete on public.booking_messages from anon, authenticated;
revoke insert, update, delete on public.viewing_appointments from anon, authenticated;
revoke insert, delete on public.reviews from anon, authenticated;
revoke all on public.payment_provider_events from anon, authenticated;

commit;
