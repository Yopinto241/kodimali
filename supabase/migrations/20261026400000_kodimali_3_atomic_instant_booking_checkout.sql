-- KODIMALI 3.0: deterministic public quote plus atomic Instant Booking
-- checkout. Payment remains disabled unless the rollout flags are approved.

alter table public.booking_policies
  add column if not exists cancellation_policy_version_id uuid
  references public.cancellation_policy_versions(id) on delete restrict;

create or replace function public.booking_unit_count(
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_period public.price_period
)
returns integer
language plpgsql
immutable
set search_path = public
as $$
declare
  v_units integer;
begin
  if p_start_at is null or p_end_at is null or p_end_at<=p_start_at then
    raise exception 'A valid booking period is required';
  end if;
  v_units:=case p_period
    when 'hour' then ceil(extract(epoch from (p_end_at-p_start_at))/3600.0)::integer
    when 'day' then ceil(extract(epoch from (p_end_at-p_start_at))/86400.0)::integer
    when 'week' then ceil(extract(epoch from (p_end_at-p_start_at))/604800.0)::integer
    when 'month' then ceil(extract(epoch from (p_end_at-p_start_at))/(86400.0*30))::integer
    when 'year' then ceil(extract(epoch from (p_end_at-p_start_at))/(86400.0*365))::integer
  end;
  return greatest(v_units,1);
end;
$$;

create or replace function public.get_public_listing_booking_quote(
  p_listing_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_listing public.listings;
  v_config public.booking_configurations;
  v_policy public.booking_policies;
  v_cancellation public.cancellation_policy_versions;
  v_agreement_version integer;
  v_capability jsonb;
  v_units integer;
  v_base bigint;
  v_service_fee bigint:=0;
  v_tax bigint:=0;
  v_total bigint;
  v_deposit bigint;
  v_balance bigint;
  v_breakdown jsonb;
  v_fingerprint text;
begin
  if p_start_at is null or p_end_at is null or p_end_at<=p_start_at then
    raise exception 'A valid booking period is required';
  end if;
  select * into v_listing from public.listings where id=p_listing_id;
  if v_listing.id is null or not public.is_listing_public(v_listing.id) then
    return null;
  end if;
  v_capability:=public.get_public_listing_booking_capability(v_listing.id);
  if coalesce(v_capability->>'effective_mode','request_booking')<>'instant_booking' then
    return jsonb_build_object(
      'booking_mode',coalesce(v_capability->>'effective_mode','request_booking')
    );
  end if;
  select * into v_config from public.booking_configurations
  where listing_id=v_listing.id;
  select * into v_policy from public.booking_policies where id=v_config.policy_id
    and is_active and active_from<=now() and (active_until is null or active_until>now());
  if v_policy.id is null then raise exception 'The booking policy is unavailable'; end if;
  select * into v_cancellation from public.cancellation_policy_versions
  where id=v_policy.cancellation_policy_version_id and is_active
    and effective_from<=now() and (effective_until is null or effective_until>now());
  if v_cancellation.id is null then
    raise exception 'The booking policy is not linked to an active cancellation policy';
  end if;
  select v.version into v_agreement_version
  from public.owner_booking_agreement_acceptances a
  join public.owner_booking_agreement_versions v on v.id=a.agreement_version_id
  where a.owner_id=v_config.authorized_by_owner_id and v.is_active and v.effective_from<=now()
  order by v.version desc limit 1;
  if v_agreement_version is null then raise exception 'The owner agreement is unavailable'; end if;

  v_units:=public.booking_unit_count(p_start_at,p_end_at,v_listing.price_period);
  v_base:=round(v_listing.price_amount*v_units)::bigint;
  if coalesce(v_policy.fee_configuration->>'service_fee_tzs','')~'^\d+(\.\d+)?$' then
    v_service_fee:=round((v_policy.fee_configuration->>'service_fee_tzs')::numeric)::bigint;
  end if;
  if coalesce(v_policy.fee_configuration->>'tax_tzs','')~'^\d+(\.\d+)?$' then
    v_tax:=round((v_policy.fee_configuration->>'tax_tzs')::numeric)::bigint;
  end if;
  v_total:=v_base+v_service_fee+v_tax;
  if v_total<=0 then raise exception 'The listing does not have a payable deterministic price'; end if;
  select s.deposit_minor,s.balance_minor into v_deposit,v_balance
  from public.calculate_booking_split(v_total,25) s;
  v_breakdown:=jsonb_build_object(
    'unit_price_tzs',round(v_listing.price_amount)::bigint,
    'price_period',v_listing.price_period::text,
    'units',v_units,
    'base_price_tzs',v_base,
    'service_fee_tzs',v_service_fee,
    'tax_tzs',v_tax,
    'total_tzs',v_total
  );
  v_fingerprint:=encode(digest(convert_to(
    jsonb_build_object(
      'listing_id',v_listing.id,'start_at',p_start_at,'end_at',p_end_at,
      'price_breakdown',v_breakdown,'policy_id',v_policy.id,
      'policy_version',v_policy.version,'cancellation_policy_version_id',v_cancellation.id,
      'agreement_version',v_agreement_version
    )::text,'UTF8'),'sha256'),'hex');
  return jsonb_build_object(
    'booking_mode','instant_booking','currency','TZS',
    'start_at',p_start_at,'end_at',p_end_at,
    'price_breakdown',v_breakdown,'total_tzs',v_total,
    'deposit_tzs',v_deposit,'balance_tzs',v_balance,
    'deposit_percent',25,'policy_id',v_policy.id,
    'cancellation_policy',jsonb_build_object(
      'policy_version_id',v_cancellation.id,'code',v_cancellation.code,
      'version',v_cancellation.version,'title',v_policy.title,'body',v_policy.body,
      'applies_to',v_cancellation.applies_to,'timezone',v_cancellation.timezone,
      'configuration',v_policy.cancellation_configuration
    ),
    'provider_obligations',v_config.fulfillment_configuration,
    'agreement_version','owner-v'||v_agreement_version,
    'quote_fingerprint',v_fingerprint
  );
end;
$$;

create or replace function public.create_instant_booking_checkout(
  p_listing_id uuid,
  p_customer_name text,
  p_customer_phone_number text,
  p_customer_email text,
  p_requested_start_at timestamptz,
  p_requested_end_at timestamptz,
  p_guest_count integer,
  p_request_message text,
  p_requested_service_codes jsonb,
  p_expected_total_tzs bigint,
  p_quote_fingerprint text,
  p_terms_accepted boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid:=auth.uid();
  v_listing public.listings;
  v_config public.booking_configurations;
  v_booking public.booking_requests;
  v_quote jsonb;
  v_snapshot public.booking_terms_snapshots;
  v_deposit bigint;
  v_balance bigint;
begin
  if v_user_id is null then raise exception 'Authentication is required' using errcode='42501'; end if;
  if not exists(select 1 from public.profiles where id=v_user_id) then
    raise exception 'Customer profile was not found' using errcode='23503';
  end if;
  if not coalesce(p_terms_accepted,false) then raise exception 'Accept the booking terms before continuing'; end if;
  if nullif(trim(coalesce(p_customer_name,'')),'') is null then raise exception 'Customer name is required'; end if;
  if nullif(trim(coalesce(p_customer_phone_number,'')),'') is null
     and nullif(trim(coalesce(p_customer_email,'')),'') is null then
    raise exception 'Email or phone number is required';
  end if;

  select * into v_listing from public.listings where id=p_listing_id for update;
  if v_listing.id is null or not public.is_listing_public(v_listing.id) then
    raise exception 'Listing is not accepting bookings';
  end if;
  select * into v_config from public.booking_configurations where listing_id=v_listing.id;
  v_quote:=public.get_public_listing_booking_quote(
    v_listing.id,p_requested_start_at,p_requested_end_at
  );
  if coalesce(v_quote->>'booking_mode','')<>'instant_booking' then
    raise exception 'Instant Booking is not available for this listing';
  end if;
  if (v_quote->>'total_tzs')::bigint<>p_expected_total_tzs
     or v_quote->>'quote_fingerprint'<>trim(coalesce(p_quote_fingerprint,'')) then
    raise exception 'The booking price or terms changed. Review the updated quote before paying' using errcode='40001';
  end if;

  insert into public.booking_requests(
    listing_id,customer_id,customer_name,customer_phone_number,customer_email,
    requested_start_at,requested_end_at,guest_count,request_message,
    requested_service_codes,policy_id,policy_accepted_at
  ) values(
    v_listing.id,v_user_id,trim(p_customer_name),nullif(trim(p_customer_phone_number),''),
    nullif(lower(trim(p_customer_email)),''),p_requested_start_at,p_requested_end_at,
    p_guest_count,nullif(trim(p_request_message),''),coalesce(p_requested_service_codes,'[]'::jsonb),
    v_config.policy_id,now()
  ) returning * into v_booking;

  select * into v_booking from public.booking_requests where id=v_booking.id;
  if v_booking.booking_status<>'reserved'
     or not exists(select 1 from public.asset_reservations where booking_request_id=v_booking.id and status='held') then
    raise exception 'The selected period could not be reserved';
  end if;
  v_deposit:=(v_quote->>'deposit_tzs')::bigint;
  v_balance:=(v_quote->>'balance_tzs')::bigint;
  insert into public.booking_terms_snapshots(
    booking_request_id,version,agreed_total_minor,deposit_minor,balance_minor,
    tax_minor,service_fee_minor,price_breakdown,booking_inputs,
    cancellation_policy_snapshot,provider_obligations_snapshot,
    agreement_version,cancellation_policy_version_id,status,offered_by,accepted_by,accepted_at
  ) values(
    v_booking.id,1,(v_quote->>'total_tzs')::bigint,v_deposit,v_balance,
    coalesce((v_quote->'price_breakdown'->>'tax_tzs')::bigint,0),
    coalesce((v_quote->'price_breakdown'->>'service_fee_tzs')::bigint,0),
    v_quote->'price_breakdown',jsonb_build_object(
      'requested_start_at',p_requested_start_at,'requested_end_at',p_requested_end_at,
      'guest_count',p_guest_count,'requested_service_codes',coalesce(p_requested_service_codes,'[]'::jsonb)
    ),v_quote->'cancellation_policy',v_quote->'provider_obligations',
    v_quote->>'agreement_version',(v_quote->'cancellation_policy'->>'policy_version_id')::uuid,
    'accepted',v_config.authorized_by_profile_id,
    v_user_id,now()
  ) returning * into v_snapshot;

  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(v_user_id,'instant_booking_checkout_created','booking_requests',v_booking.id,
    jsonb_build_object('snapshot_id',v_snapshot.id,'total_tzs',v_snapshot.agreed_total_minor,
      'deposit_tzs',v_snapshot.deposit_minor,'quote_fingerprint',p_quote_fingerprint));
  return jsonb_build_object(
    'booking_request_id',v_booking.id,'request_reference',v_booking.request_reference,
    'booking_status',v_booking.booking_status,'booking_mode','instant_booking',
    'payment_required',true,'terms_snapshot_id',v_snapshot.id,
    'total_tzs',v_snapshot.agreed_total_minor,'deposit_tzs',v_snapshot.deposit_minor,
    'balance_tzs',v_snapshot.balance_minor
  );
end;
$$;

revoke all on function public.booking_unit_count(timestamptz,timestamptz,public.price_period) from public;
grant execute on function public.booking_unit_count(timestamptz,timestamptz,public.price_period) to anon,authenticated,service_role;
revoke all on function public.get_public_listing_booking_quote(uuid,timestamptz,timestamptz) from public;
grant execute on function public.get_public_listing_booking_quote(uuid,timestamptz,timestamptz) to anon,authenticated,service_role;
revoke all on function public.create_instant_booking_checkout(uuid,text,text,text,timestamptz,timestamptz,integer,text,jsonb,bigint,text,boolean) from public,anon,authenticated;
grant execute on function public.create_instant_booking_checkout(uuid,text,text,text,timestamptz,timestamptz,integer,text,jsonb,bigint,text,boolean) to authenticated,service_role;

comment on function public.create_instant_booking_checkout(uuid,text,text,text,timestamptz,timestamptz,integer,text,jsonb,bigint,text,boolean) is
'Atomically revalidates an accepted public quote, holds verified inventory and stores immutable accepted terms. It does not collect payment.';
