-- Published, verified inventory is pre-authorized for instant reservation.
-- A signed-in customer receives an atomic 30-minute hold before payment.

create or replace function public.enforce_verified_reservable_booking()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_category text;
  v_asset_id uuid;
  v_controller_verified boolean := false;
begin
  select c.slug, l.asset_id,
    (
      exists (
        select 1
        from public.owner_asset_claims oc
        join public.owner_profiles op on op.id = oc.owner_id
        where oc.asset_id = l.asset_id
          and oc.status = 'verified'
          and oc.authority_type in ('owner','authorized_manager')
          and op.verification_status = 'verified'
      )
      or (ag.verification_status = 'approved' and ag.account_status = 'active')
    )
  into v_category, v_asset_id, v_controller_verified
  from public.listings l
  join public.asset_categories c on c.id = l.category_id
  left join public.agents ag on ag.id = l.agent_id
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
    if not v_controller_verified then
      raise exception 'A verified owner, manager or listing agent is required before booking';
    end if;

    new.booking_kind := 'reservation';
    -- Publishing verified inventory is the controller's authorization to sell
    -- the displayed availability. Viewing and manual re-approval are optional.
    new.owner_approval_status := 'not_required';
    new.owner_response_deadline := null;
  end if;
  return new;
end;
$$;

create or replace function public.create_instant_booking_hold()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_asset_id uuid;
  v_category text;
  v_hold_until timestamptz := now() + interval '30 minutes';
begin
  if new.customer_id is null
     or new.requested_start_at is null
     or new.requested_end_at is null
     or new.booking_status in ('confirmed','completed','cancelled','rejected') then
    return new;
  end if;

  select l.asset_id, c.slug
  into v_asset_id, v_category
  from public.listings l
  join public.asset_categories c on c.id = l.category_id
  where l.id = new.listing_id
    and public.is_listing_public(l.id);

  if v_category not in ('house','apartment','car','motorcycle','office','meeting-hall','ceremony-hall')
     or v_asset_id is null then
    return new;
  end if;

  update public.asset_reservations r
  set status = 'expired', updated_at = now()
  from public.booking_requests b
  where r.booking_request_id = b.id
    and r.status = 'held'
    and b.payment_expires_at <= now();

  insert into public.asset_reservations(
    asset_id, booking_request_id, occupied_period, status, created_by
  ) values (
    v_asset_id, new.id,
    tstzrange(new.requested_start_at,new.requested_end_at,'[)'),
    'held', new.customer_id
  )
  on conflict (booking_request_id) do update
    set status = case
      when public.asset_reservations.status = 'confirmed' then 'confirmed'
      else 'held'
    end,
    occupied_period = excluded.occupied_period,
    updated_at = now();

  update public.booking_requests
  set booking_kind = 'reservation',
      booking_status = 'reserved',
      owner_approval_status = 'not_required',
      owner_response_deadline = null,
      accepted_at = coalesce(accepted_at, now()),
      payment_ready_at = coalesce(payment_ready_at, now()),
      payment_expires_at = v_hold_until,
      updated_at = now()
  where id = new.id;

  return new;
exception when exclusion_violation then
  raise exception 'The selected period has just been reserved. Choose another time.'
    using errcode = '23P01';
end;
$$;

drop trigger if exists create_instant_booking_hold on public.booking_requests;
create trigger create_instant_booking_hold
after insert or update of customer_id
on public.booking_requests
for each row execute function public.create_instant_booking_hold();

create or replace function public.prepare_booking_for_payment(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare b public.booking_requests; amount numeric; asset uuid; hold_until timestamptz;
begin
 select * into b from public.booking_requests where id=p_booking_id and customer_id=auth.uid() for update;
 if b.id is null then raise exception 'Booking was not found'; end if;
 if b.requested_start_at is null or b.requested_end_at is null or b.requested_end_at<=b.requested_start_at then raise exception 'Valid booking dates are required'; end if;
 if b.owner_approval_status not in ('not_required','approved') then raise exception 'This booking is not ready for payment'; end if;
 select asset_id into asset from public.listings where id=b.listing_id;
 if asset is null then raise exception 'This listing is not connected to reservable inventory'; end if;
 update public.asset_reservations r set status='expired',updated_at=now()
 from public.booking_requests x where r.booking_request_id=x.id and r.status='held' and x.payment_expires_at<=now();
 if exists(select 1 from public.asset_reservations r where r.asset_id=asset and r.booking_request_id<>b.id and r.status in('held','confirmed') and r.occupied_period&&tstzrange(b.requested_start_at,b.requested_end_at,'[)')) then raise exception 'The selected period is no longer available' using errcode='23P01'; end if;
 hold_until := case when b.payment_expires_at is not null and b.payment_expires_at>now() then b.payment_expires_at else now()+interval '30 minutes' end;
 insert into public.asset_reservations(asset_id,booking_request_id,occupied_period,status,created_by)
 values(asset,b.id,tstzrange(b.requested_start_at,b.requested_end_at,'[)'),'held',auth.uid())
 on conflict(booking_request_id) do update set status=case when public.asset_reservations.status='confirmed' then 'confirmed' else 'held' end,updated_at=now();
 select coalesce(nullif((p.fee_configuration->>'reservation_fee_tzs')::numeric,0),s.booking_reservation_fee_tzs)
 into amount from public.marketplace_settings s left join public.booking_policies p on p.id=b.policy_id where s.id=true;
 update public.booking_requests set booking_kind='reservation',booking_status='reserved',owner_approval_status='not_required',accepted_at=coalesce(accepted_at,now()),payment_ready_at=coalesce(payment_ready_at,now()),policy_accepted_at=coalesce(policy_accepted_at,now()),payment_expires_at=hold_until,updated_at=now() where id=b.id;
 return jsonb_build_object('amount_tzs',amount,'customer_id',b.customer_id,'asset_id',asset,'hold_expires_at',hold_until);
end $$;

create or replace function public.expire_booking_holds()
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.asset_reservations r set status='expired',updated_at=now()
  from public.booking_requests b
  where r.booking_request_id=b.id and r.status='held' and b.payment_expires_at<=now();
  update public.booking_requests b set booking_status='cancelled',updated_at=now()
  where b.booking_status='reserved' and b.payment_expires_at<=now()
    and not exists(select 1 from public.booking_payment_transactions p where p.booking_request_id=b.id and p.status='paid');
end $$;
revoke all on function public.expire_booking_holds() from public;
grant execute on function public.expire_booking_holds() to service_role;

do $$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  perform cron.unschedule(jobid) from cron.job where jobname='expire-booking-holds';
  perform cron.schedule('expire-booking-holds','*/2 * * * *','select public.expire_booking_holds()');
 end if;
end $$;

