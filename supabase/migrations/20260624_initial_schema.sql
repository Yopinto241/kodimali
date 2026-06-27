create extension if not exists pgcrypto;

create type public.app_role as enum ('customer', 'agent', 'admin', 'owner');
create type public.listing_category as enum (
  'house',
  'car',
  'motorcycle',
  'office',
  'meeting_hall',
  'ceremony_hall',
  'equipment',
  'other_asset'
);
create type public.listing_status as enum (
  'draft',
  'active',
  'inactive',
  'expired',
  'suspended'
);
create type public.approval_status as enum ('pending', 'approved', 'rejected');
create type public.price_period as enum ('hour', 'day', 'week', 'month', 'year');
create type public.availability_status as enum (
  'available',
  'reserved',
  'rented',
  'unavailable'
);
create type public.agent_verification_status as enum ('pending', 'approved', 'rejected');
create type public.location_type as enum (
  'country',
  'region',
  'district',
  'ward',
  'area',
  'street'
);
create type public.media_type as enum ('image', 'video');
create type public.booking_status as enum (
  'new',
  'checking_availability',
  'contacted',
  'viewing_scheduled',
  'reserved',
  'confirmed',
  'completed',
  'cancelled',
  'rejected',
  'no_response',
  'agent_delayed'
);
create type public.notification_type as enum (
  'booking_received',
  'booking_created',
  'booking_status_changed',
  'agent_verified',
  'listing_approved',
  'report_created',
  'agent_delayed',
  'announcement'
);
create type public.report_status as enum ('open', 'in_review', 'resolved', 'dismissed');

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  phone_number text,
  avatar_url text,
  preferred_language text not null default 'sw',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.user_roles (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  role public.app_role not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (profile_id, role)
);

create table if not exists public.agents (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles (id) on delete cascade,
  business_name text,
  verification_status public.agent_verification_status not null default 'pending',
  verified_at timestamptz,
  admin_notes text,
  average_response_minutes numeric(8, 2),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.agent_documents (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references public.agents (id) on delete cascade,
  document_type text not null,
  storage_path text not null,
  review_notes text,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.locations (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.locations (id) on delete cascade,
  location_type public.location_type not null,
  name text not null,
  latitude numeric(10, 7),
  longitude numeric(10, 7),
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists idx_locations_unique_name_per_parent
  on public.locations (coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), location_type, lower(name));

create table if not exists public.owners (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references public.agents (id) on delete cascade,
  full_name text not null,
  phone_number text not null,
  location_id uuid references public.locations (id) on delete set null,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.listings (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references public.agents (id) on delete cascade,
  owner_id uuid references public.owners (id) on delete set null,
  category public.listing_category not null,
  title text not null,
  description text not null,
  location_id uuid not null references public.locations (id) on delete restrict,
  public_location_label text not null,
  exact_address text,
  map_pin_latitude numeric(10, 7),
  map_pin_longitude numeric(10, 7),
  price_amount numeric(12, 2) not null check (price_amount >= 0),
  price_period public.price_period not null,
  deposit_required_amount numeric(12, 2) default 0 check (deposit_required_amount >= 0),
  listing_rules text,
  status public.listing_status not null default 'draft',
  approval_status public.approval_status not null default 'pending',
  availability_status public.availability_status not null default 'available',
  expires_at timestamptz,
  published_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.listing_media (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  media_type public.media_type not null,
  storage_path text not null,
  thumbnail_path text,
  display_order integer not null default 0,
  is_cover boolean not null default false,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.property_details (
  listing_id uuid primary key references public.listings (id) on delete cascade,
  bedrooms integer,
  bathrooms integer,
  rooms integer,
  is_furnished boolean,
  water_availability text,
  parking boolean,
  security boolean,
  electricity text,
  office_size_sqm numeric(10, 2),
  internet_available boolean,
  monthly_price numeric(12, 2),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.vehicle_details (
  listing_id uuid primary key references public.listings (id) on delete cascade,
  brand text,
  model text,
  year_of_make integer,
  transmission text,
  fuel_type text,
  driver_included boolean not null default false,
  deposit_required_amount numeric(12, 2),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.venue_details (
  listing_id uuid primary key references public.listings (id) on delete cascade,
  capacity integer,
  price_per_hour numeric(12, 2),
  price_per_day numeric(12, 2),
  chairs_available integer,
  tables_available integer,
  sound_system boolean not null default false,
  projector boolean not null default false,
  kitchen boolean not null default false,
  parking boolean not null default false,
  toilets_count integer,
  power_backup boolean not null default false,
  event_rules text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.availability_blocks (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  block_reason text not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  check (end_at > start_at)
);

create table if not exists public.booking_requests (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  customer_id uuid not null references public.profiles (id) on delete cascade,
  agent_id uuid not null references public.agents (id) on delete cascade,
  requested_start_at timestamptz not null,
  requested_end_at timestamptz not null,
  booking_status public.booking_status not null default 'new',
  request_message text,
  agent_response_due_at timestamptz,
  first_agent_response_at timestamptz,
  admin_override boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (requested_end_at > requested_start_at)
);

create table if not exists public.booking_status_history (
  id uuid primary key default gen_random_uuid(),
  booking_request_id uuid not null references public.booking_requests (id) on delete cascade,
  status public.booking_status not null,
  changed_by uuid references public.profiles (id) on delete set null,
  reason text,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  device_token text not null unique,
  platform text not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  booking_request_id uuid references public.booking_requests (id) on delete set null,
  type public.notification_type not null,
  title text not null,
  body text not null,
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid references public.listings (id) on delete cascade,
  reported_by uuid not null references public.profiles (id) on delete cascade,
  report_reason text not null,
  details text,
  status public.report_status not null default 'open',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  booking_request_id uuid not null unique references public.booking_requests (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  customer_id uuid not null references public.profiles (id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles (id) on delete set null,
  action text not null,
  target_table text not null,
  target_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create or replace function public.is_admin(check_user uuid default auth.uid())
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.user_roles
    where profile_id = check_user
      and role = 'admin'
  );
$$;

create index if not exists idx_listings_search
  on public.listings (category, location_id, approval_status, status);

create index if not exists idx_booking_requests_listing_time
  on public.booking_requests (listing_id, booking_status, requested_start_at, requested_end_at);

create index if not exists idx_booking_requests_agent_status
  on public.booking_requests (agent_id, booking_status, created_at desc);

create index if not exists idx_availability_blocks_listing_time
  on public.availability_blocks (listing_id, start_at, end_at);

create index if not exists idx_notifications_user_created
  on public.notifications (user_id, created_at desc);

create trigger set_profiles_updated_at
before update on public.profiles
for each row execute procedure public.set_updated_at();

create trigger set_agents_updated_at
before update on public.agents
for each row execute procedure public.set_updated_at();

create trigger set_owners_updated_at
before update on public.owners
for each row execute procedure public.set_updated_at();

create trigger set_listings_updated_at
before update on public.listings
for each row execute procedure public.set_updated_at();

create trigger set_property_details_updated_at
before update on public.property_details
for each row execute procedure public.set_updated_at();

create trigger set_vehicle_details_updated_at
before update on public.vehicle_details
for each row execute procedure public.set_updated_at();

create trigger set_venue_details_updated_at
before update on public.venue_details
for each row execute procedure public.set_updated_at();

create trigger set_booking_requests_updated_at
before update on public.booking_requests
for each row execute procedure public.set_updated_at();

create trigger set_device_tokens_updated_at
before update on public.device_tokens
for each row execute procedure public.set_updated_at();

create trigger set_reports_updated_at
before update on public.reports
for each row execute procedure public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.agents enable row level security;
alter table public.agent_documents enable row level security;
alter table public.locations enable row level security;
alter table public.owners enable row level security;
alter table public.listings enable row level security;
alter table public.listing_media enable row level security;
alter table public.property_details enable row level security;
alter table public.vehicle_details enable row level security;
alter table public.venue_details enable row level security;
alter table public.availability_blocks enable row level security;
alter table public.booking_requests enable row level security;
alter table public.booking_status_history enable row level security;
alter table public.device_tokens enable row level security;
alter table public.notifications enable row level security;
alter table public.reports enable row level security;
alter table public.reviews enable row level security;
alter table public.audit_logs enable row level security;

create policy "profiles_self_or_admin_select"
on public.profiles
for select
using (auth.uid() = id or public.is_admin());

create policy "profiles_self_update"
on public.profiles
for update
using (auth.uid() = id)
with check (auth.uid() = id);

create policy "user_roles_self_or_admin_select"
on public.user_roles
for select
using (auth.uid() = profile_id or public.is_admin());

create policy "agents_public_verified_or_owner_select"
on public.agents
for select
using (
  verification_status = 'approved'
  or profile_id = auth.uid()
  or public.is_admin()
);

create policy "agents_self_update"
on public.agents
for update
using (profile_id = auth.uid() or public.is_admin())
with check (profile_id = auth.uid() or public.is_admin());

create policy "agent_documents_agent_or_admin_all"
on public.agent_documents
for all
using (
  exists (
    select 1 from public.agents
    where public.agents.id = agent_documents.agent_id
      and public.agents.profile_id = auth.uid()
  )
  or public.is_admin()
)
with check (
  exists (
    select 1 from public.agents
    where public.agents.id = agent_documents.agent_id
      and public.agents.profile_id = auth.uid()
  )
  or public.is_admin()
);

create policy "locations_active_select"
on public.locations
for select
using (is_active or public.is_admin());

create policy "locations_admin_all"
on public.locations
for all
using (public.is_admin())
with check (public.is_admin());

create policy "owners_agent_or_admin_all"
on public.owners
for all
using (
  exists (
    select 1 from public.agents
    where public.agents.id = owners.agent_id
      and public.agents.profile_id = auth.uid()
  )
  or public.is_admin()
)
with check (
  exists (
    select 1 from public.agents
    where public.agents.id = owners.agent_id
      and public.agents.profile_id = auth.uid()
  )
  or public.is_admin()
);

create policy "listings_public_select_approved"
on public.listings
for select
using (
  (approval_status = 'approved' and status = 'active')
  or public.is_admin()
  or exists (
    select 1 from public.agents
    where public.agents.id = listings.agent_id
      and public.agents.profile_id = auth.uid()
  )
);

create policy "listings_agent_or_admin_all"
on public.listings
for all
using (
  public.is_admin()
  or exists (
    select 1 from public.agents
    where public.agents.id = listings.agent_id
      and public.agents.profile_id = auth.uid()
  )
)
with check (
  public.is_admin()
  or exists (
    select 1 from public.agents
    where public.agents.id = listings.agent_id
      and public.agents.profile_id = auth.uid()
  )
);

create policy "listing_media_follow_listing_visibility_select"
on public.listing_media
for select
using (
  exists (
    select 1
    from public.listings
    where public.listings.id = listing_media.listing_id
      and (
        (public.listings.approval_status = 'approved' and public.listings.status = 'active')
        or public.is_admin()
        or exists (
          select 1 from public.agents
          where public.agents.id = public.listings.agent_id
            and public.agents.profile_id = auth.uid()
        )
      )
  )
);

create policy "listing_media_agent_or_admin_all"
on public.listing_media
for all
using (
  public.is_admin()
  or exists (
    select 1
    from public.listings
    join public.agents on public.agents.id = public.listings.agent_id
    where public.listings.id = listing_media.listing_id
      and public.agents.profile_id = auth.uid()
  )
)
with check (
  public.is_admin()
  or exists (
    select 1
    from public.listings
    join public.agents on public.agents.id = public.listings.agent_id
    where public.listings.id = listing_media.listing_id
      and public.agents.profile_id = auth.uid()
  )
);

create policy "property_details_follow_listing_visibility"
on public.property_details
for select
using (
  exists (
    select 1 from public.listings
    where public.listings.id = property_details.listing_id
      and (
        (public.listings.approval_status = 'approved' and public.listings.status = 'active')
        or public.is_admin()
        or exists (
          select 1 from public.agents
          where public.agents.id = public.listings.agent_id
            and public.agents.profile_id = auth.uid()
        )
      )
  )
);

create policy "property_details_agent_or_admin_all"
on public.property_details
for all
using (
  public.is_admin()
  or exists (
    select 1 from public.listings
    join public.agents on public.agents.id = public.listings.agent_id
    where public.listings.id = property_details.listing_id
      and public.agents.profile_id = auth.uid()
  )
)
with check (
  public.is_admin()
  or exists (
    select 1 from public.listings
    join public.agents on public.agents.id = public.listings.agent_id
    where public.listings.id = property_details.listing_id
      and public.agents.profile_id = auth.uid()
  )
);

create policy "vehicle_details_follow_listing_visibility"
on public.vehicle_details
for select
using (
  exists (
    select 1 from public.listings
    where public.listings.id = vehicle_details.listing_id
      and (
        (public.listings.approval_status = 'approved' and public.listings.status = 'active')
        or public.is_admin()
        or exists (
          select 1 from public.agents
          where public.agents.id = public.listings.agent_id
            and public.agents.profile_id = auth.uid()
        )
      )
  )
);

create policy "vehicle_details_agent_or_admin_all"
on public.vehicle_details
for all
using (
  public.is_admin()
  or exists (
    select 1 from public.listings
    join public.agents on public.agents.id = public.listings.agent_id
    where public.listings.id = vehicle_details.listing_id
      and public.agents.profile_id = auth.uid()
  )
)
with check (
  public.is_admin()
  or exists (
    select 1 from public.listings
    join public.agents on public.agents.id = public.listings.agent_id
    where public.listings.id = vehicle_details.listing_id
      and public.agents.profile_id = auth.uid()
  )
);

create policy "venue_details_follow_listing_visibility"
on public.venue_details
for select
using (
  exists (
    select 1 from public.listings
    where public.listings.id = venue_details.listing_id
      and (
        (public.listings.approval_status = 'approved' and public.listings.status = 'active')
        or public.is_admin()
        or exists (
          select 1 from public.agents
          where public.agents.id = public.listings.agent_id
            and public.agents.profile_id = auth.uid()
        )
      )
  )
);

create policy "venue_details_agent_or_admin_all"
on public.venue_details
for all
using (
  public.is_admin()
  or exists (
    select 1 from public.listings
    join public.agents on public.agents.id = public.listings.agent_id
    where public.listings.id = venue_details.listing_id
      and public.agents.profile_id = auth.uid()
  )
)
with check (
  public.is_admin()
  or exists (
    select 1 from public.listings
    join public.agents on public.agents.id = public.listings.agent_id
    where public.listings.id = venue_details.listing_id
      and public.agents.profile_id = auth.uid()
  )
);

create policy "availability_blocks_agent_or_admin_all"
on public.availability_blocks
for all
using (
  public.is_admin()
  or exists (
    select 1 from public.listings
    join public.agents on public.agents.id = public.listings.agent_id
    where public.listings.id = availability_blocks.listing_id
      and public.agents.profile_id = auth.uid()
  )
)
with check (
  public.is_admin()
  or exists (
    select 1 from public.listings
    join public.agents on public.agents.id = public.listings.agent_id
    where public.listings.id = availability_blocks.listing_id
      and public.agents.profile_id = auth.uid()
  )
);

create policy "booking_requests_customer_agent_admin_select"
on public.booking_requests
for select
using (
  customer_id = auth.uid()
  or public.is_admin()
  or exists (
    select 1 from public.agents
    where public.agents.id = booking_requests.agent_id
      and public.agents.profile_id = auth.uid()
  )
);

create policy "booking_requests_customer_insert"
on public.booking_requests
for insert
with check (customer_id = auth.uid());

create policy "booking_requests_customer_agent_admin_update"
on public.booking_requests
for update
using (
  customer_id = auth.uid()
  or public.is_admin()
  or exists (
    select 1 from public.agents
    where public.agents.id = booking_requests.agent_id
      and public.agents.profile_id = auth.uid()
  )
)
with check (
  customer_id = auth.uid()
  or public.is_admin()
  or exists (
    select 1 from public.agents
    where public.agents.id = booking_requests.agent_id
      and public.agents.profile_id = auth.uid()
  )
);

create policy "booking_history_visible_to_booking_participants"
on public.booking_status_history
for select
using (
  exists (
    select 1
    from public.booking_requests
    where public.booking_requests.id = booking_status_history.booking_request_id
      and (
        public.booking_requests.customer_id = auth.uid()
        or public.is_admin()
        or exists (
          select 1 from public.agents
          where public.agents.id = public.booking_requests.agent_id
            and public.agents.profile_id = auth.uid()
        )
      )
  )
);

create policy "device_tokens_self_all"
on public.device_tokens
for all
using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

create policy "notifications_self_select"
on public.notifications
for select
using (user_id = auth.uid() or public.is_admin());

create policy "notifications_self_update"
on public.notifications
for update
using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

create policy "reports_reporter_or_admin_select"
on public.reports
for select
using (reported_by = auth.uid() or public.is_admin());

create policy "reports_reporter_insert"
on public.reports
for insert
with check (reported_by = auth.uid());

create policy "reports_admin_update"
on public.reports
for update
using (public.is_admin())
with check (public.is_admin());

create policy "reviews_public_select"
on public.reviews
for select
using (true);

create policy "reviews_customer_insert"
on public.reviews
for insert
with check (customer_id = auth.uid());

create policy "audit_logs_admin_select"
on public.audit_logs
for select
using (public.is_admin());
