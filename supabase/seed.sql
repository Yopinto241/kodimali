insert into public.locations (id, parent_id, location_type, name, latitude, longitude)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', null, 'country', 'Tanzania', -6.3690, 34.8888),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'region', 'Arusha', -3.3869, 36.6830),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'district', 'Arusha City', -3.3667, 36.6833),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'ward', 'Njiro', -3.4010, 36.7508),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa5', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', 'area', 'Kwa Mrombo', -3.4031, 36.7544)
on conflict (id) do nothing;

insert into public.profiles (id, full_name, phone_number, preferred_language)
select auth_user.id, seed.full_name, seed.phone_number, seed.preferred_language
from (
  values
    ('11111111-1111-1111-1111-111111111111'::uuid, 'Admin User', '+255700000001', 'sw'),
    ('22222222-2222-2222-2222-222222222222'::uuid, 'Amina Customer', '+255700000002', 'sw'),
    ('33333333-3333-3333-3333-333333333333'::uuid, 'Baraka Agent', '+255700000003', 'sw')
) as seed(id, full_name, phone_number, preferred_language)
join auth.users as auth_user on auth_user.id = seed.id
on conflict (id) do nothing;

insert into public.user_roles (profile_id, role)
select profile_id, role::public.app_role
from (
  values
    ('11111111-1111-1111-1111-111111111111'::uuid, 'admin'),
    ('22222222-2222-2222-2222-222222222222'::uuid, 'customer'),
    ('33333333-3333-3333-3333-333333333333'::uuid, 'agent')
) as seed(profile_id, role)
where exists (
  select 1 from public.profiles where public.profiles.id = seed.profile_id
)
on conflict do nothing;

insert into public.agents (id, profile_id, business_name, verification_status, verified_at)
select
  '44444444-4444-4444-4444-444444444444'::uuid,
  '33333333-3333-3333-3333-333333333333'::uuid,
  'Baraka Rentals',
  'approved',
  now()
where exists (
  select 1 from public.profiles where id = '33333333-3333-3333-3333-333333333333'::uuid
)
on conflict (id) do nothing;

insert into public.owners (id, agent_id, full_name, phone_number, location_id)
select
  '55555555-5555-5555-5555-555555555555'::uuid,
  '44444444-4444-4444-4444-444444444444'::uuid,
  'Moses Owner',
  '+255700000004',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa5'::uuid
where exists (
  select 1 from public.agents where id = '44444444-4444-4444-4444-444444444444'::uuid
)
on conflict (id) do nothing;

insert into public.listings (
  id,
  agent_id,
  owner_id,
  category,
  title,
  description,
  location_id,
  public_location_label,
  price_amount,
  price_period,
  deposit_required_amount,
  listing_rules,
  status,
  approval_status,
  availability_status,
  published_at,
  expires_at
)
select
  '66666666-6666-6666-6666-666666666666'::uuid,
  '44444444-4444-4444-4444-444444444444'::uuid,
  '55555555-5555-5555-5555-555555555555'::uuid,
  'meeting_hall',
  'Ukumbi wa Mikutano Arusha Central',
  'Ukumbi wa watu 120 wenye projector, parking, na jenereta.',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa5'::uuid,
  'Njiro, Arusha',
  350000,
  'day',
  100000,
  'Hakuna uvutaji sigara ndani ya ukumbi.',
  'active',
  'approved',
  'available',
  now(),
  now() + interval '45 days'
where exists (
  select 1 from public.agents where id = '44444444-4444-4444-4444-444444444444'::uuid
)
on conflict (id) do nothing;

insert into public.venue_details (
  listing_id,
  capacity,
  price_per_day,
  chairs_available,
  tables_available,
  sound_system,
  projector,
  kitchen,
  parking,
  toilets_count,
  power_backup,
  event_rules
)
select
  '66666666-6666-6666-6666-666666666666'::uuid,
  120,
  350000,
  120,
  20,
  true,
  true,
  true,
  true,
  4,
  true,
  'Hakuna uvutaji sigara ndani ya ukumbi.'
where exists (
  select 1 from public.listings where id = '66666666-6666-6666-6666-666666666666'::uuid
)
on conflict (listing_id) do nothing;

insert into public.listing_media (
  id,
  listing_id,
  media_type,
  storage_path,
  thumbnail_path,
  display_order,
  is_cover
)
select
  '77777777-7777-7777-7777-777777777777'::uuid,
  '66666666-6666-6666-6666-666666666666'::uuid,
  'image',
  'listing-media/meeting-hall-cover.jpg',
  'listing-media/meeting-hall-cover-thumb.jpg',
  1,
  true
where exists (
  select 1 from public.listings where id = '66666666-6666-6666-6666-666666666666'::uuid
)
on conflict (id) do nothing;
