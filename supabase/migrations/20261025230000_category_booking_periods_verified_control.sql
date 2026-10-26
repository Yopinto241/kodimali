-- Category-wide reservations require a real period, verified inventory and a
-- verified owner or authorized manager with a verified claim to that asset.

create or replace function public.enforce_verified_reservable_booking()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_category text;
  v_asset_id uuid;
begin
  select c.slug, l.asset_id
    into v_category, v_asset_id
  from public.listings l
  join public.asset_categories c on c.id = l.category_id
  where l.id = new.listing_id;

  if v_category in ('house','apartment','car','motorcycle','office','meeting-hall','ceremony-hall')
     and (new.requested_start_at is not null
          or new.requested_end_at is not null
          or new.booking_kind = 'reservation') then
    if new.requested_start_at is null or new.requested_end_at is null
       or new.requested_end_at <= new.requested_start_at then
      raise exception 'A valid booking start and end period is required';
    end if;
    if v_asset_id is null then
      raise exception 'This listing is not connected to verified inventory';
    end if;
    if not exists (
      select 1 from public.rental_assets a
      where a.id = v_asset_id and a.verification_status = 'verified'
    ) then
      raise exception 'The listed item must be verified before it can accept bookings';
    end if;
    if not exists (
      select 1
      from public.owner_asset_claims c
      join public.owner_profiles o on o.id = c.owner_id
      where c.asset_id = v_asset_id
        and c.status = 'verified'
        and c.authority_type in ('owner','authorized_manager')
        and o.verification_status = 'verified'
    ) then
      raise exception 'A verified owner or authorized manager is required before booking';
    end if;

    new.booking_kind := 'reservation';
    if new.owner_approval_status in ('not_required','expired') then
      new.owner_approval_status := 'pending';
      new.owner_response_deadline := now() + interval '24 hours';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_verified_reservable_booking on public.booking_requests;
create trigger enforce_verified_reservable_booking
before insert or update of listing_id, booking_kind, requested_start_at, requested_end_at
on public.booking_requests
for each row execute function public.enforce_verified_reservable_booking();

create or replace function public.listing_booking_readiness(p_listing_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'ready',
      l.asset_id is not null
      and a.verification_status = 'verified'
      and exists (
        select 1 from public.owner_asset_claims c
        join public.owner_profiles o on o.id = c.owner_id
        where c.asset_id = l.asset_id
          and c.status = 'verified'
          and c.authority_type in ('owner','authorized_manager')
          and o.verification_status = 'verified'
      ),
    'asset_verified', coalesce(a.verification_status = 'verified', false),
    'verified_controller', exists (
      select 1 from public.owner_asset_claims c
      join public.owner_profiles o on o.id = c.owner_id
      where c.asset_id = l.asset_id
        and c.status = 'verified'
        and c.authority_type in ('owner','authorized_manager')
        and o.verification_status = 'verified'
    )
  )
  from public.listings l
  left join public.rental_assets a on a.id = l.asset_id
  where l.id = p_listing_id
    and public.is_listing_public(l.id);
$$;

revoke all on function public.listing_booking_readiness(uuid) from public;
grant execute on function public.listing_booking_readiness(uuid) to anon, authenticated, service_role;
