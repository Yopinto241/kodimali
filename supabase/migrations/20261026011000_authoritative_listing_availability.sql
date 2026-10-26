create or replace function public.check_listing_period_availability(
  p_listing_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_asset_id uuid;
  v_public boolean;
  v_conflicts integer := 0;
begin
  if p_start_at is null or p_end_at is null or p_end_at <= p_start_at then
    raise exception 'A valid start and end period is required';
  end if;
  select l.asset_id, public.is_listing_public(l.id)
  into v_asset_id, v_public
  from public.listings l where l.id=p_listing_id;
  if not found then return jsonb_build_object('available',false,'reason','Listing not found'); end if;
  if not coalesce(v_public,false) then return jsonb_build_object('available',false,'reason','Listing is not active on the marketplace'); end if;

  update public.asset_reservations r set status='expired',updated_at=now()
  from public.booking_requests b
  where r.booking_request_id=b.id and r.status='held' and b.payment_expires_at<=now();

  select
    (select count(*) from public.availability_blocks x
      where x.listing_id=p_listing_id and x.start_at<p_end_at and x.end_at>p_start_at)
    +
    (select count(*) from public.asset_reservations r
      where r.asset_id=v_asset_id and r.status in ('held','confirmed')
        and r.occupied_period && tstzrange(p_start_at,p_end_at,'[)'))
  into v_conflicts;

  return jsonb_build_object(
    'available',v_conflicts=0,
    'reason',case when v_conflicts=0 then null else 'The listing is not available for the selected period' end
  );
end;
$$;
revoke all on function public.check_listing_period_availability(uuid,timestamptz,timestamptz) from public;
grant execute on function public.check_listing_period_availability(uuid,timestamptz,timestamptz) to anon,authenticated,service_role;

