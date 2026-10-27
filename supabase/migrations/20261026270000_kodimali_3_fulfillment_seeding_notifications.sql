-- KODIMALI 3.0: create category-specific fulfillment work after verified
-- booking payment and notify both customer and assigned provider.

create or replace function public.seed_booking_fulfillment_milestones(
  p_booking_request_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.booking_requests;
  v_category text;
  v_inserted integer := 0;
begin
  select b.* into v_booking
  from public.booking_requests b
  where b.id = p_booking_request_id;
  if v_booking.id is null then
    raise exception 'Booking not found';
  end if;

  select c.slug into v_category
  from public.listings l
  join public.asset_categories c on c.id = l.category_id
  where l.id = v_booking.listing_id;

  if v_category in ('house','apartment') then
    insert into public.fulfillment_milestones(booking_request_id,milestone_kind,due_at,status)
    values
      (v_booking.id,'handover',v_booking.requested_start_at,'ready'),
      (v_booking.id,'tenancy_start',v_booking.requested_start_at,'pending')
    on conflict(booking_request_id,milestone_kind) do nothing;
  elsif v_category in ('car','motorcycle') then
    insert into public.fulfillment_milestones(booking_request_id,milestone_kind,due_at,status)
    values
      (v_booking.id,'vehicle_pickup',v_booking.requested_start_at,'ready'),
      (v_booking.id,'vehicle_return',v_booking.requested_end_at,'pending')
    on conflict(booking_request_id,milestone_kind) do nothing;
  elsif v_category = 'office' then
    insert into public.fulfillment_milestones(booking_request_id,milestone_kind,due_at,status)
    values
      (v_booking.id,'handover',v_booking.requested_start_at,'ready'),
      (v_booking.id,'period_completed',v_booking.requested_end_at,'pending')
    on conflict(booking_request_id,milestone_kind) do nothing;
  elsif v_category in ('meeting-hall','ceremony-hall') then
    insert into public.fulfillment_milestones(booking_request_id,milestone_kind,due_at,status)
    values
      (v_booking.id,'venue_access',v_booking.requested_start_at,'ready'),
      (v_booking.id,'period_completed',v_booking.requested_end_at,'pending')
    on conflict(booking_request_id,milestone_kind) do nothing;
  end if;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

create or replace function public.after_verified_booking_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.booking_requests;
  v_provider_profile uuid;
  v_title text;
begin
  if new.status <> 'paid' or new.kind not in ('reservation','deposit','balance') then
    return new;
  end if;

  select b.* into v_booking from public.booking_requests b where b.id=new.booking_request_id;
  select l.title into v_title from public.listings l where l.id=v_booking.listing_id;
  select a.profile_id into v_provider_profile from public.agents a where a.id=v_booking.agent_id;

  if new.kind in ('reservation','deposit') then
    perform public.seed_booking_fulfillment_milestones(new.booking_request_id);
  end if;

  insert into public.notifications(user_id,booking_request_id,type,title,body,payload)
  values(
    v_booking.customer_id,
    v_booking.id,
    'announcement',
    case when new.kind='balance' then 'Booking balance received' else 'Booking deposit received' end,
    case when new.kind='balance'
      then 'Your remaining booking balance is confirmed.'
      else 'Your deposit is confirmed and the booking is secured.'
    end,
    jsonb_build_object(
      'eventType','booking_payment_verified',
      'bookingId',v_booking.id,
      'listingTitle',v_title,
      'paymentKind',new.kind,
      'amountTzs',new.amount_tzs,
      'route','account/request/'||v_booking.id::text
    )
  );

  if v_provider_profile is not null then
    insert into public.notifications(user_id,booking_request_id,type,title,body,payload)
    values(
      v_provider_profile,
      v_booking.id,
      'announcement',
      case when new.kind='balance' then 'Customer paid booking balance' else 'Confirmed booking received' end,
      case when new.kind='balance'
        then 'The customer balance is verified. Review the upcoming fulfillment tasks.'
        else 'The customer deposit is verified. Prepare the confirmed booking.'
      end,
      jsonb_build_object(
        'eventType','provider_booking_payment_verified',
        'bookingId',v_booking.id,
        'listingTitle',v_title,
        'paymentKind',new.kind,
        'route','bookings/'||v_booking.id::text
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists after_verified_booking_payment on public.booking_payment_transactions;
create trigger after_verified_booking_payment
after insert on public.booking_payment_transactions
for each row execute function public.after_verified_booking_payment();

revoke all on function public.seed_booking_fulfillment_milestones(uuid) from public, anon, authenticated;
grant execute on function public.seed_booking_fulfillment_milestones(uuid) to service_role;
revoke all on function public.after_verified_booking_payment() from public, anon, authenticated;

comment on function public.seed_booking_fulfillment_milestones(uuid) is
'Idempotently creates category-specific provider/customer fulfillment steps after verified booking payment.';
