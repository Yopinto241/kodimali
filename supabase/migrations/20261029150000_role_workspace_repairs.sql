-- Repair role workflows against the current schema. Preserve existing function grants.

do $$ begin
 if not exists(select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='report_status') then
  create type public.report_status as enum ('open','in_review','resolved','dismissed');
 end if;
end $$;
create table if not exists public.reports (
 id uuid primary key default gen_random_uuid(),
 listing_id uuid references public.listings(id) on delete cascade,
 reported_by uuid not null references public.profiles(id) on delete cascade,
 report_reason text not null check(length(trim(report_reason))>0), details text,
 status public.report_status not null default 'open',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.reports enable row level security;
drop trigger if exists set_reports_updated_at on public.reports;
create trigger set_reports_updated_at before update on public.reports
 for each row execute function public.set_updated_at();
revoke all on public.reports from public,anon,authenticated;
grant all on public.reports to service_role;
grant select,insert on public.reports to authenticated;
grant update(status,updated_at) on public.reports to authenticated;
drop policy if exists "reports_reporter_or_admin_select" on public.reports;
drop policy if exists "reports_reporter_insert" on public.reports;
drop policy if exists "reports_admin_update" on public.reports;
create policy reports_read on public.reports for select to authenticated
 using(reported_by=auth.uid() or public.has_admin_permission('reports.manage'));
create policy reports_submit on public.reports for insert to authenticated
 with check(reported_by=auth.uid() and status='open' and listing_id is not null and public.is_listing_public(listing_id));
create policy reports_review on public.reports for update to authenticated
 using(public.has_admin_permission('reports.manage')) with check(public.has_admin_permission('reports.manage'));
create index if not exists reports_listing_status_idx on public.reports(listing_id,status);

CREATE OR REPLACE FUNCTION public.accept_tenant_invitation(p_token text)
 RETURNS tenant_invitations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare r public.tenant_invitations; begin if auth.uid() is null then raise exception 'Authentication required'; end if; select * into r from public.tenant_invitations where token_hash=encode(extensions.digest(trim(p_token),'sha256'),'hex') for update; if r.id is null or r.status<>'pending' or r.expires_at<=now() then raise exception 'Invitation is invalid or expired'; end if; update public.tenant_invitations set status='accepted',accepted_by=auth.uid(),accepted_at=now() where id=r.id returning * into r; return r; end $function$
;

CREATE OR REPLACE FUNCTION public.agent_trust_summary(p_agent_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.agents%rowtype; v_response numeric; v_completed bigint; v_total bigint; v_responded bigint; v_rating numeric; v_reviews bigint; v_complaints bigint; v_plan text;
begin
 select * into a from public.agents where id=p_agent_id;
 if not found then return '{}'::jsonb; end if;
 select round(avg(extract(epoch from(first_agent_response_at-created_at))/60)::numeric,1),count(*),count(first_agent_response_at) into v_response,v_total,v_responded from public.booking_requests where agent_id=p_agent_id;
 select count(*) into v_completed from public.booking_requests where agent_id=p_agent_id and booking_status='completed';
 select round(avg(r.rating)::numeric,2),count(*) into v_rating,v_reviews from public.reviews r join public.booking_requests b on b.id=r.booking_request_id where b.agent_id=p_agent_id and r.moderation_status='visible';
 select count(*) into v_complaints from public.reports rp join public.listings l on l.id=rp.listing_id where l.agent_id=p_agent_id and rp.status in ('open','in_review');
 select s.plan_id into v_plan from public.agent_subscriptions s where s.agent_id=p_agent_id and s.status='active' and (s.expires_at is null or s.expires_at>now()) limit 1;
 return jsonb_build_object('verified',a.verification_status='approved','account_age_days',floor(extract(epoch from(now()-a.created_at))/86400),'response_minutes',coalesce(v_response,a.average_response_minutes),'completed',v_completed,'response_rate',case when v_total=0 then 0 else round(100.0*v_responded/v_total,1) end,'rating',coalesce(v_rating,0),'reviews',v_reviews,'complaints',v_complaints,'plan',coalesce(v_plan,'free'));
end $function$
;

CREATE OR REPLACE FUNCTION public.configure_owned_listing_booking(p_listing_id uuid, p_booking_mode text, p_policy_id uuid DEFAULT NULL::uuid, p_deterministic_pricing boolean DEFAULT false, p_availability_reliable boolean DEFAULT false, p_hold_duration_minutes integer DEFAULT 30, p_balance_deadline_configuration jsonb DEFAULT '{}'::jsonb, p_fulfillment_configuration jsonb DEFAULT '{}'::jsonb)
 RETURNS booking_configurations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    if v_listing.status<>'active' or v_listing.publication_review_status not in ('auto_approved','admin_approved')
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
        and (p.category is null or p.category=(select a.category from public.rental_assets a where a.id=v_listing.asset_id))
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
$function$
;

CREATE OR REPLACE FUNCTION public.confirm_customer_fulfillment_milestone(p_milestone_id uuid)
 RETURNS fulfillment_milestones
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_milestone public.fulfillment_milestones;
  v_customer_id uuid;
begin
  select m.*
  into v_milestone
  from public.fulfillment_milestones m
  where m.id = p_milestone_id
  for update of m;

  if v_milestone.id is null then
    raise exception 'Fulfillment milestone not found';
  end if;

  select b.customer_id
  into v_customer_id
  from public.booking_requests b
  where b.id = v_milestone.booking_request_id;

  if v_customer_id is distinct from auth.uid() then
    raise exception 'Only the booking customer can confirm this milestone';
  end if;
  if v_milestone.status in ('verified','customer_confirmed') then
    return v_milestone;
  end if;
  if v_milestone.status in ('failed','disputed','waived') then
    raise exception 'This milestone cannot be customer-confirmed';
  end if;

  update public.fulfillment_milestones
  set status = 'customer_confirmed',
      customer_confirmed_at = coalesce(customer_confirmed_at, now()),
      updated_at = now()
  where id = p_milestone_id
  returning * into v_milestone;

  insert into public.audit_logs(actor_id, action, target_table, target_id, metadata)
  values(
    auth.uid(),
    'fulfillment_milestone_customer_confirmed',
    'fulfillment_milestones',
    p_milestone_id,
    jsonb_build_object(
      'booking_request_id', v_milestone.booking_request_id,
      'milestone_kind', v_milestone.milestone_kind
    )
  );
  return v_milestone;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_admin_listing_chat_conversation(p_conversation_id uuid)
 RETURNS TABLE(id uuid, listing_id uuid, listing_title text, agent_id uuid, agent_name text, customer_id uuid, customer_name text, status text, expires_at timestamp with time zone, messages jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_admin_permission('support.manage') then
    raise exception 'Support permission required' using errcode='42501';
  end if;
  if not exists(select 1 from public.listing_conversations existing where existing.id=p_conversation_id) then
    raise exception 'Conversation was not found' using errcode='P0002';
  end if;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'listing_chat_viewed','listing_conversations',p_conversation_id,'{}'::jsonb);
  return query
  select c.id,c.listing_id,l.title,c.agent_id,coalesce(a.business_name,a.display_name,'Agent'),
    c.customer_id,coalesce(p.full_name,'Customer'),c.status,x.expires_at,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',m.id,
          'sender_id',m.sender_id,
          'body',m.body,
          'read_at',m.read_at,
          'created_at',m.created_at
        ) order by m.created_at
      )
      from public.listing_chat_messages m
      where m.conversation_id=c.id
    ),'[]'::jsonb)
  from public.listing_conversations c
  join public.listings l on l.id=c.listing_id
  join public.agents a on a.id=c.agent_id
  join public.profiles p on p.id=c.customer_id
  left join public.listing_chat_access x on x.customer_id=c.customer_id and x.agent_id=c.agent_id and x.listing_id=c.listing_id
  where c.id=p_conversation_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.get_public_listing_booking_quote(p_listing_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_fingerprint:=encode(extensions.digest(convert_to(
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
$function$
;

CREATE OR REPLACE FUNCTION public.invite_tenant(p_asset_id uuid, p_email text DEFAULT NULL::text, p_phone_number text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare oid uuid:=public.current_owner_id(); raw_token text:=encode(extensions.gen_random_bytes(24),'hex'); r public.tenant_invitations; begin if oid is null then raise exception 'Verified owner access required'; end if; if not exists(select 1 from public.owner_asset_claims where owner_id=oid and asset_id=p_asset_id and status='verified') then raise exception 'Verified asset control required'; end if; insert into public.tenant_invitations(owner_id,asset_id,email,phone_number,token_hash,invited_by,expires_at) values(oid,p_asset_id,nullif(lower(trim(p_email)),''),nullif(trim(p_phone_number),''),encode(extensions.digest(raw_token,'sha256'),'hex'),auth.uid(),now()+interval '7 days') returning * into r; return jsonb_build_object('id',r.id,'token',raw_token,'expires_at',r.expires_at); end $function$
;

-- Resolve permissions through the same active-role predicate as server actions.
create or replace function public.get_my_admin_permissions() returns jsonb
language sql stable security definer set search_path=public as $$
 select case when public.is_super_admin() then '["*"]'::jsonb else coalesce((
  select jsonb_agg(distinct permission) from public.admin_role_assignments a
  join public.admin_role_definitions r on r.id=a.role_id
  cross join lateral jsonb_array_elements_text(r.permissions) permission
  where a.user_id=auth.uid() and r.is_active
 ),'[]'::jsonb) end
$$;
revoke all on function public.get_my_admin_permissions() from public,anon;
grant execute on function public.get_my_admin_permissions() to authenticated,service_role;
