-- KODIMALI 3.0: verified owners explicitly control booking eligibility for
-- assets they have proved authority over. Listing authorship alone is not
-- sufficient and existing confirmed reservations are never modified here.

create or replace function public.configure_owned_listing_booking(
  p_listing_id uuid,
  p_booking_mode text,
  p_policy_id uuid default null,
  p_deterministic_pricing boolean default false,
  p_availability_reliable boolean default false,
  p_hold_duration_minutes integer default 30,
  p_balance_deadline_configuration jsonb default '{}'::jsonb,
  p_fulfillment_configuration jsonb default '{}'::jsonb
)
returns public.booking_configurations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner public.owner_profiles;
  v_listing public.listings;
  v_config public.booking_configurations;
begin
  if p_booking_mode not in ('not_bookable','request_booking','instant_booking') then
    raise exception 'Unsupported booking mode';
  end if;
  if p_hold_duration_minutes not between 5 and 60 then
    raise exception 'Hold duration must be between 5 and 60 minutes';
  end if;
  if jsonb_typeof(coalesce(p_balance_deadline_configuration,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_fulfillment_configuration,'{}'::jsonb))<>'object' then
    raise exception 'Booking configuration details must be JSON objects';
  end if;
  select * into v_owner from public.owner_profiles
  where profile_id=auth.uid() and verification_status='verified';
  if v_owner.id is null then raise exception 'Verified owner access required'; end if;
  select * into v_listing from public.listings where id=p_listing_id for update;
  if v_listing.id is null then raise exception 'Listing not found'; end if;
  if v_listing.asset_id is null or not exists(
    select 1 from public.owner_asset_claims c
    where c.owner_id=v_owner.id and c.asset_id=v_listing.asset_id and c.status='verified'
  ) then raise exception 'Verified authority over this asset is required'; end if;

  if p_booking_mode='instant_booking' then
    if v_listing.status<>'active' or v_listing.approval_status<>'approved'
       or not exists(select 1 from public.rental_assets a where a.id=v_listing.asset_id and a.verification_status='verified') then
      raise exception 'The listing and canonical asset must be active and verified';
    end if;
    if not p_deterministic_pricing or not p_availability_reliable then
      raise exception 'Instant Booking requires deterministic pricing and reliable availability';
    end if;
    if p_policy_id is null or not exists(
      select 1 from public.booking_policies p
      where p.id=p_policy_id and p.is_active=true
        and p.active_from<=now() and (p.active_until is null or p.active_until>now())
        and (p.category is null or p.category=v_listing.category)
    ) then raise exception 'Choose an active booking policy for this category'; end if;
    if not exists(
      select 1 from public.owner_booking_agreement_acceptances a
      join public.owner_booking_agreement_versions v on v.id=a.agreement_version_id
      where a.owner_id=v_owner.id and v.is_active=true and v.effective_from<=now()
    ) then raise exception 'Accept the active owner booking agreement first'; end if;
  end if;

  insert into public.booking_configurations(
    listing_id,asset_id,booking_mode,authority_status,deterministic_pricing,
    availability_reliable,policy_id,hold_duration_minutes,
    balance_deadline_configuration,fulfillment_configuration,
    authorized_by_owner_id,authorized_by_profile_id,authorized_at,configured_by
  ) values(
    v_listing.id,v_listing.asset_id,p_booking_mode,'verified',p_deterministic_pricing,
    p_availability_reliable,p_policy_id,p_hold_duration_minutes,
    coalesce(p_balance_deadline_configuration,'{}'::jsonb),
    coalesce(p_fulfillment_configuration,'{}'::jsonb),
    v_owner.id,auth.uid(),now(),auth.uid()
  ) on conflict(listing_id) do update set
    asset_id=excluded.asset_id,
    booking_mode=excluded.booking_mode,
    authority_status='verified',
    deterministic_pricing=excluded.deterministic_pricing,
    availability_reliable=excluded.availability_reliable,
    policy_id=excluded.policy_id,
    hold_duration_minutes=excluded.hold_duration_minutes,
    balance_deadline_configuration=excluded.balance_deadline_configuration,
    fulfillment_configuration=excluded.fulfillment_configuration,
    authorized_by_owner_id=excluded.authorized_by_owner_id,
    authorized_by_profile_id=excluded.authorized_by_profile_id,
    authorized_at=now(),configured_by=auth.uid(),updated_at=now()
  returning * into v_config;

  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'owner_booking_configuration_changed','booking_configurations',v_config.id,
    jsonb_build_object('listing_id',v_listing.id,'asset_id',v_listing.asset_id,
      'booking_mode',p_booking_mode,'hold_duration_minutes',p_hold_duration_minutes,
      'policy_id',p_policy_id));
  return v_config;
end;
$$;

revoke all on function public.configure_owned_listing_booking(uuid,text,uuid,boolean,boolean,integer,jsonb,jsonb)
from public,anon,authenticated;
grant execute on function public.configure_owned_listing_booking(uuid,text,uuid,boolean,boolean,integer,jsonb,jsonb)
to authenticated,service_role;

comment on function public.configure_owned_listing_booking(uuid,text,uuid,boolean,boolean,integer,jsonb,jsonb) is
'Verified-owner booking control; it never grants authority from listing authorship and never cancels existing reservations.';

