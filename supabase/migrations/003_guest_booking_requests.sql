alter table public.booking_requests
  alter column customer_id drop not null,
  alter column requested_start_at drop not null,
  alter column requested_end_at drop not null;

alter table public.booking_requests
  add column if not exists customer_name text,
  add column if not exists customer_phone_number text,
  add column if not exists customer_email text,
  add column if not exists request_reference text;

alter table public.listings
  add column if not exists removed_from_market_at timestamptz,
  add column if not exists removed_reason text;

update public.booking_requests as br
set
  customer_name = coalesce(br.customer_name, p.full_name),
  customer_phone_number = coalesce(br.customer_phone_number, p.phone_number)
from public.profiles as p
where p.id = br.customer_id;

drop trigger if exists populate_booking_customer_contact on public.booking_requests;
drop function if exists public.populate_booking_customer_contact();

alter table public.booking_requests
  drop constraint if exists booking_requests_no_confirmed_overlap;

create sequence if not exists public.booking_request_reference_seq;

create or replace function public.generate_booking_request_reference()
returns text
language plpgsql
as $$
declare
  next_number bigint;
begin
  next_number := nextval('public.booking_request_reference_seq');
  return format(
    'KDM-%s-%s',
    to_char(timezone('utc', now()), 'YYYY'),
    lpad(next_number::text, 6, '0')
  );
end;
$$;

create or replace function public.prepare_guest_booking_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_listing public.listings%rowtype;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;

  if new.customer_name is null or btrim(new.customer_name) = '' then
    raise exception 'customer_name is required';
  end if;

  if new.customer_phone_number is null or btrim(new.customer_phone_number) = '' then
    raise exception 'customer_phone_number is required';
  end if;

  select *
  into v_listing
  from public.listings
  where id = new.listing_id;

  if v_listing.id is null then
    raise exception 'Listing was not found';
  end if;

  if v_listing.approval_status <> 'approved'::public.approval_status
     or v_listing.status <> 'active'::public.listing_status then
    raise exception 'Listing is not available for public requests';
  end if;

  new.agent_id := v_listing.agent_id;
  new.customer_id := null;
  new.request_reference := coalesce(new.request_reference, public.generate_booking_request_reference());

  return new;
end;
$$;

drop trigger if exists prepare_guest_booking_request on public.booking_requests;
create trigger prepare_guest_booking_request
before insert on public.booking_requests
for each row execute function public.prepare_guest_booking_request();

drop policy if exists "booking_requests_customer_agent_admin_select" on public.booking_requests;
drop policy if exists "booking_requests_customer_insert" on public.booking_requests;
drop policy if exists "booking_requests_customer_agent_admin_update" on public.booking_requests;
drop policy if exists "booking_history_visible_to_booking_participants" on public.booking_status_history;

create policy "booking_requests_agent_admin_select"
on public.booking_requests
for select
using (
  public.is_admin()
  or exists (
    select 1 from public.agents
    where public.agents.id = booking_requests.agent_id
      and public.agents.profile_id = auth.uid()
  )
);

create policy "booking_requests_agent_admin_update"
on public.booking_requests
for update
using (
  public.is_admin()
  or exists (
    select 1 from public.agents
    where public.agents.id = booking_requests.agent_id
      and public.agents.profile_id = auth.uid()
  )
)
with check (
  public.is_admin()
  or exists (
    select 1 from public.agents
    where public.agents.id = booking_requests.agent_id
      and public.agents.profile_id = auth.uid()
  )
);

create policy "booking_history_visible_to_agent_or_admin"
on public.booking_status_history
for select
using (
  exists (
    select 1
    from public.booking_requests
    where public.booking_requests.id = booking_status_history.booking_request_id
      and (
        public.is_admin()
        or exists (
          select 1 from public.agents
          where public.agents.id = public.booking_requests.agent_id
            and public.agents.profile_id = auth.uid()
        )
      )
  )
);

create unique index if not exists idx_booking_requests_request_reference
  on public.booking_requests (request_reference)
  where request_reference is not null;

create or replace view public.listing_inquiry_counts as
select
  listing_id,
  count(*)::int as inquiry_count
from public.booking_requests
group by listing_id;

create or replace function public.guard_listing_workflow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_admin(auth.uid()) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.approval_status is distinct from 'pending'::public.approval_status then
      raise exception 'Agents cannot set approval_status on insert';
    end if;

    if new.status is distinct from 'draft'::public.listing_status then
      raise exception 'Agents can only create draft listings';
    end if;

    new.published_at := null;
    return new;
  end if;

  if new.approval_status = 'approved'::public.approval_status then
    if old.approval_status is distinct from 'approved'::public.approval_status then
      raise exception 'Only admin can approve listings';
    end if;
  end if;

  if new.approval_status is distinct from old.approval_status then
    if not (
      old.approval_status = 'rejected'::public.approval_status
      and new.approval_status = 'pending'::public.approval_status
    ) then
      raise exception 'Only admin can approve or reject listings';
    end if;
  end if;

  if new.status = 'suspended'::public.listing_status or new.status = 'expired'::public.listing_status then
    raise exception 'Only admin can suspend or expire listings';
  end if;

  if old.approval_status = 'approved'::public.approval_status then
    if new.status not in ('active'::public.listing_status, 'inactive'::public.listing_status) then
      raise exception 'Approved listings can only move between active and inactive for agents';
    end if;
  else
    if new.status is distinct from 'draft'::public.listing_status then
      raise exception 'Agents cannot publish listings before admin approval';
    end if;
  end if;

  new.published_at := old.published_at;
  return new;
end;
$$;

drop trigger if exists guard_listing_workflow on public.listings;
create trigger guard_listing_workflow
before insert or update on public.listings
for each row execute function public.guard_listing_workflow();
