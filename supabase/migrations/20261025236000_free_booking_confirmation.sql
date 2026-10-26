create or replace function public.confirm_free_booking(p_booking_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare b public.booking_requests;v_asset uuid;
begin
  if public.payment_feature_enabled('booking_reservation') then
    raise exception 'Booking payment is currently required';
  end if;
  select * into b from public.booking_requests
  where id=p_booking_id and customer_id=auth.uid() for update;
  if b.id is null then raise exception 'Booking was not found'; end if;
  if b.accepted_at is null then raise exception 'The agent must accept this booking first'; end if;
  if b.owner_approval_status not in ('not_required','approved') then
    raise exception 'Owner approval is required before confirmation';
  end if;
  select asset_id into v_asset from public.listings where id=b.listing_id;
  if v_asset is null then raise exception 'This listing is not connected to reservable inventory'; end if;
  insert into public.asset_reservations(asset_id,booking_request_id,occupied_period,status,created_by)
  values(v_asset,b.id,tstzrange(b.requested_start_at,b.requested_end_at,'[)'),'confirmed',auth.uid())
  on conflict(booking_request_id) do update set status='confirmed',updated_at=now();
  update public.booking_requests set booking_status='confirmed',updated_at=now() where id=b.id;
  return jsonb_build_object('success',true,'booking_id',b.id,'status','confirmed');
exception when exclusion_violation then
  raise exception 'The selected period is no longer available' using errcode='23P01';
end;
$$;

revoke all on function public.confirm_free_booking(uuid) from public;
grant execute on function public.confirm_free_booking(uuid) to authenticated;

