-- Owner authorization must not depend on public marketing visibility of a listing.
create or replace function public.is_verified_owner_booking(p_listing_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.listings l
    join public.owner_asset_claims c on c.asset_id=l.asset_id
    join public.owner_profiles o on o.id=c.owner_id
    where l.id=p_listing_id and c.status='verified'
      and o.profile_id=auth.uid() and o.verification_status='verified');
$$;
revoke all on function public.is_verified_owner_booking(uuid) from public,anon;
grant execute on function public.is_verified_owner_booking(uuid) to authenticated,service_role;
alter policy booking_requests_owner_read on public.booking_requests
using (public.is_verified_owner_booking(listing_id));
