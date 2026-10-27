-- KODIMALI 3.0: make booking_configurations authoritative over the legacy
-- reservation trigger. A reservable category alone never implies Instant
-- Booking, and a disabled global flag safely falls back to Request Booking.

create or replace function public.apply_listing_booking_mode()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_mode text;
begin
  if new.requested_start_at is null or new.requested_end_at is null then return new; end if;
  select coalesce(c.booking_mode,'request_booking') into v_mode
  from public.booking_configurations c where c.listing_id=new.listing_id;
  v_mode:=coalesce(v_mode,'request_booking');
  if v_mode='not_bookable' then raise exception 'This listing is not accepting bookings'; end if;
  new.booking_kind:='reservation';
  return new;
end;
$$;

drop trigger if exists a_apply_listing_booking_mode on public.booking_requests;
create trigger a_apply_listing_booking_mode
before insert or update of listing_id,requested_start_at,requested_end_at
on public.booking_requests
for each row execute function public.apply_listing_booking_mode();

create or replace function public.create_instant_booking_hold()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_asset_id uuid;
  v_listing_id uuid;
  v_category text;
  v_hold_until timestamptz;
begin
  if new.customer_id is null or new.requested_start_at is null
     or new.requested_end_at is null
     or new.booking_status in ('confirmed','completed','cancelled','rejected')
     or not public.kodimali_feature_enabled('instant_booking')
     or not public.kodimali_feature_enabled('booking_deposit_payments') then
    return new;
  end if;

  select l.asset_id,l.id,c.slug
  into v_asset_id,v_listing_id,v_category
  from public.listings l
  join public.asset_categories c on c.id=l.category_id
  join public.booking_configurations bc on bc.listing_id=l.id
  where l.id=new.listing_id
    and public.is_listing_public(l.id)
    and bc.booking_mode='instant_booking'
    and bc.authority_status='verified'
    and bc.deterministic_pricing=true
    and bc.availability_reliable=true
    and bc.policy_id is not null
    and bc.authorized_by_owner_id is not null
    and bc.authorized_at is not null
    and exists(
      select 1 from public.rental_assets a
      where a.id=l.asset_id and a.verification_status='verified'
    )
    and exists(
      select 1 from public.owner_asset_claims oc
      where oc.asset_id=l.asset_id and oc.owner_id=bc.authorized_by_owner_id
        and oc.status='verified'
    );

  if v_category not in ('house','apartment','car','motorcycle','office','meeting-hall','ceremony-hall')
     or v_asset_id is null then return new; end if;

  update public.asset_reservations r set status='expired',updated_at=now()
  from public.booking_requests b
  where r.booking_request_id=b.id and r.status='held' and b.payment_expires_at<=now();
  v_hold_until:=now()+make_interval(
    mins=>public.resolve_booking_hold_minutes(v_listing_id,'instant_booking')
  );
  insert into public.asset_reservations(
    asset_id,booking_request_id,occupied_period,status,created_by
  ) values(
    v_asset_id,new.id,tstzrange(new.requested_start_at,new.requested_end_at,'[)'),
    'held',new.customer_id
  ) on conflict(booking_request_id) do update set
    status=case when public.asset_reservations.status='confirmed' then 'confirmed' else 'held' end,
    occupied_period=excluded.occupied_period,updated_at=now();
  update public.booking_requests set
    booking_kind='reservation',booking_status='reserved',
    owner_approval_status='not_required',owner_response_deadline=null,
    accepted_at=coalesce(accepted_at,now()),
    payment_ready_at=coalesce(payment_ready_at,now()),
    payment_expires_at=v_hold_until,updated_at=now()
  where id=new.id;
  return new;
exception when exclusion_violation then
  raise exception 'The selected period has just been reserved. Choose another time.' using errcode='23P01';
end;
$$;

create or replace function public.get_public_listing_booking_capability(
  p_listing_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'configured_mode',coalesce(bc.booking_mode,'request_booking'),
    'effective_mode',case
      when coalesce(bc.booking_mode,'request_booking')='not_bookable' then 'not_bookable'
      when bc.booking_mode='instant_booking'
        and public.kodimali_feature_enabled('instant_booking')
        and public.kodimali_feature_enabled('booking_deposit_payments')
        and bc.authority_status='verified' and bc.deterministic_pricing
        and bc.availability_reliable and bc.policy_id is not null
        and bc.authorized_by_owner_id is not null and bc.authorized_at is not null
        and exists(select 1 from public.rental_assets a where a.id=l.asset_id and a.verification_status='verified')
        and exists(select 1 from public.owner_asset_claims oc where oc.asset_id=l.asset_id and oc.owner_id=bc.authorized_by_owner_id and oc.status='verified')
      then 'instant_booking'
      else 'request_booking'
    end,
    'deposit_payments_enabled',public.kodimali_feature_enabled('booking_deposit_payments')
  )
  from public.listings l
  left join public.booking_configurations bc on bc.listing_id=l.id
  where l.id=p_listing_id and public.is_listing_public(l.id)
$$;

revoke all on function public.apply_listing_booking_mode() from public,anon,authenticated;
revoke all on function public.get_public_listing_booking_capability(uuid) from public;
grant execute on function public.get_public_listing_booking_capability(uuid)
to anon,authenticated,service_role;

comment on function public.get_public_listing_booking_capability(uuid) is
'Public non-sensitive booking label source. The backend remains authoritative at booking and payment time.';

