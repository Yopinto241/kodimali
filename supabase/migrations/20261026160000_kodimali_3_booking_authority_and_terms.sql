-- KODIMALI 3.0 phase 1: controlled rollout, explicit booking authority and
-- immutable monetary/agreement snapshots. Additive and inactive by default.

create table if not exists public.kodimali_feature_flags (
  key text primary key,
  enabled boolean not null default false,
  configuration jsonb not null default '{}'::jsonb,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (not enabled or (approved_by is not null and approved_at is not null))
);

insert into public.kodimali_feature_flags(key) values
  ('instant_booking'),
  ('booking_deposit_payments'),
  ('booking_balance_payments'),
  ('paid_chat_unlock_v3'),
  ('contact_unlock_v3'),
  ('automated_refunds'),
  ('automated_provider_payouts'),
  ('external_deal_accounting')
on conflict (key) do nothing;

alter table public.kodimali_feature_flags enable row level security;
create policy kodimali_feature_flags_admin_read
on public.kodimali_feature_flags for select to authenticated
using (public.has_admin_permission('dashboard.view') or public.has_admin_permission('payments.view'));
create policy kodimali_feature_flags_super_admin_manage
on public.kodimali_feature_flags for all to authenticated
using (public.is_super_admin()) with check (public.is_super_admin());

create or replace function public.kodimali_feature_enabled(p_key text)
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((select enabled from public.kodimali_feature_flags where key=p_key),false)
$$;
revoke all on function public.kodimali_feature_enabled(text) from public;
grant execute on function public.kodimali_feature_enabled(text) to anon,authenticated,service_role;

create or replace function public.set_kodimali_feature_flag(p_key text,p_enabled boolean,p_configuration jsonb default null)
returns public.kodimali_feature_flags language plpgsql security definer set search_path=public as $$
declare r public.kodimali_feature_flags;
begin
  if not public.is_super_admin() then raise exception 'Super Admin permission required'; end if;
  insert into public.kodimali_feature_flags(key,enabled,configuration,approved_by,approved_at,updated_by,updated_at)
  values(p_key,p_enabled,coalesce(p_configuration,'{}'::jsonb),case when p_enabled then auth.uid() end,case when p_enabled then now() end,auth.uid(),now())
  on conflict(key) do update set enabled=excluded.enabled,
    configuration=coalesce(p_configuration,public.kodimali_feature_flags.configuration),
    approved_by=case when excluded.enabled then auth.uid() else null end,
    approved_at=case when excluded.enabled then now() else null end,
    updated_by=auth.uid(),updated_at=now()
  returning * into r;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'feature_flag_changed','kodimali_feature_flags',null,jsonb_build_object('key',p_key,'enabled',p_enabled));
  return r;
end $$;
revoke all on function public.set_kodimali_feature_flag(text,boolean,jsonb) from public;
grant execute on function public.set_kodimali_feature_flag(text,boolean,jsonb) to authenticated;

create table if not exists public.booking_configurations (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null unique references public.listings(id) on delete cascade,
  asset_id uuid references public.rental_assets(id) on delete restrict,
  booking_mode text not null default 'not_bookable' check(booking_mode in ('not_bookable','request_booking','instant_booking')),
  authority_status text not null default 'unverified' check(authority_status in ('unverified','pending','verified','revoked')),
  deterministic_pricing boolean not null default false,
  availability_reliable boolean not null default false,
  policy_id uuid references public.booking_policies(id) on delete restrict,
  balance_deadline_configuration jsonb not null default '{}'::jsonb,
  fulfillment_configuration jsonb not null default '{}'::jsonb,
  authorized_by_owner_id uuid references public.owner_profiles(id) on delete restrict,
  authorized_by_profile_id uuid references public.profiles(id) on delete restrict,
  authorized_at timestamptz,
  configured_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (booking_mode <> 'instant_booking' or (
    authority_status='verified' and deterministic_pricing and availability_reliable
    and policy_id is not null and authorized_by_owner_id is not null and authorized_at is not null
  ))
);

-- Preserve existing discovery and request behavior, but never silently enable
-- Instant Booking. Existing eligible listings start in request mode.
insert into public.booking_configurations(listing_id,asset_id,booking_mode,authority_status,configured_by)
select l.id,l.asset_id,'request_booking',
  case when l.asset_id is not null and exists(select 1 from public.rental_assets a where a.id=l.asset_id and a.verification_status='verified') then 'verified' else 'unverified' end,
  null
from public.listings l
where l.asset_id is not null
on conflict(listing_id) do nothing;

alter table public.booking_configurations enable row level security;
create policy booking_configurations_public_read on public.booking_configurations for select
using (true);
create policy booking_configurations_admin_manage on public.booking_configurations for all to authenticated
using (public.has_admin_permission('bookings.manage')) with check (public.has_admin_permission('bookings.manage'));
create policy booking_configurations_owner_manage on public.booking_configurations for all to authenticated
using (exists(select 1 from public.owner_asset_claims c where c.asset_id=booking_configurations.asset_id and c.owner_id=public.current_owner_id() and c.status='verified'))
with check (exists(select 1 from public.owner_asset_claims c where c.asset_id=booking_configurations.asset_id and c.owner_id=public.current_owner_id() and c.status='verified'));

create table if not exists public.booking_terms_snapshots (
  id uuid primary key default gen_random_uuid(),
  booking_request_id uuid not null references public.booking_requests(id) on delete restrict,
  version integer not null,
  currency text not null default 'TZS' check(currency='TZS'),
  agreed_total_minor bigint not null check(agreed_total_minor>=0),
  deposit_percent smallint not null default 25 check(deposit_percent between 1 and 100),
  deposit_minor bigint not null check(deposit_minor>=0),
  balance_minor bigint not null check(balance_minor>=0),
  tax_minor bigint not null default 0 check(tax_minor>=0),
  service_fee_minor bigint not null default 0 check(service_fee_minor>=0),
  price_breakdown jsonb not null default '{}'::jsonb,
  booking_inputs jsonb not null default '{}'::jsonb,
  cancellation_policy_snapshot jsonb not null,
  provider_obligations_snapshot jsonb not null default '{}'::jsonb,
  agreement_version text not null,
  balance_due_at timestamptz,
  service_timezone text not null default 'Africa/Dar_es_Salaam',
  status text not null default 'offered' check(status in ('offered','accepted','superseded','expired')),
  offered_by uuid not null references public.profiles(id) on delete restrict,
  offered_at timestamptz not null default now(),
  accepted_by uuid references public.profiles(id) on delete restrict,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  unique(booking_request_id,version),
  check(deposit_minor+balance_minor=agreed_total_minor),
  check(status<>'accepted' or (accepted_by is not null and accepted_at is not null))
);
create unique index if not exists booking_terms_one_accepted_idx on public.booking_terms_snapshots(booking_request_id) where status='accepted';
alter table public.booking_terms_snapshots enable row level security;
create policy booking_terms_participant_read on public.booking_terms_snapshots for select to authenticated
using(public.is_admin() or public.is_booking_participant(booking_request_id));

create or replace function public.calculate_booking_split(p_total_minor bigint,p_deposit_percent integer default 25)
returns table(deposit_minor bigint,balance_minor bigint)
language plpgsql immutable set search_path=public as $$
begin
  if p_total_minor<0 then raise exception 'Total amount cannot be negative'; end if;
  if p_deposit_percent<1 or p_deposit_percent>100 then raise exception 'Deposit percentage must be between 1 and 100'; end if;
  deposit_minor:=floor((p_total_minor::numeric*p_deposit_percent+50)/100)::bigint;
  balance_minor:=p_total_minor-deposit_minor;
  return next;
end $$;
grant execute on function public.calculate_booking_split(bigint,integer) to anon,authenticated,service_role;

create or replace function public.prevent_booking_terms_mutation()
returns trigger language plpgsql set search_path=public as $$
begin
  if old.status='accepted' then raise exception 'Accepted booking terms are immutable'; end if;
  if new.booking_request_id<>old.booking_request_id or new.version<>old.version
     or new.currency<>old.currency or new.agreed_total_minor<>old.agreed_total_minor
     or new.deposit_percent<>old.deposit_percent or new.deposit_minor<>old.deposit_minor
     or new.balance_minor<>old.balance_minor or new.tax_minor<>old.tax_minor
     or new.service_fee_minor<>old.service_fee_minor or new.price_breakdown<>old.price_breakdown
     or new.booking_inputs<>old.booking_inputs or new.cancellation_policy_snapshot<>old.cancellation_policy_snapshot
     or new.provider_obligations_snapshot<>old.provider_obligations_snapshot
     or new.agreement_version<>old.agreement_version or new.balance_due_at is distinct from old.balance_due_at
     or new.service_timezone<>old.service_timezone or new.offered_by<>old.offered_by
     or new.offered_at<>old.offered_at then
    raise exception 'Booking financial and agreement terms are immutable; create a new version';
  end if;
  return new;
end $$;
create trigger prevent_booking_terms_mutation before update on public.booking_terms_snapshots
for each row execute function public.prevent_booking_terms_mutation();

create or replace function public.offer_booking_terms(
  p_booking_request_id uuid,p_agreed_total_minor bigint,p_price_breakdown jsonb,
  p_booking_inputs jsonb,p_cancellation_policy jsonb,p_provider_obligations jsonb,
  p_agreement_version text,p_balance_due_at timestamptz default null,p_service_timezone text default 'Africa/Dar_es_Salaam'
) returns public.booking_terms_snapshots language plpgsql security definer set search_path=public as $$
declare b public.booking_requests;v_version integer;v_deposit bigint;v_balance bigint;r public.booking_terms_snapshots;v_authorized boolean:=false;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into b from public.booking_requests where id=p_booking_request_id for update;
  if b.id is null then raise exception 'Booking was not found'; end if;
  select public.is_admin() or exists(select 1 from public.agents a where a.id=b.agent_id and a.profile_id=auth.uid())
    or exists(select 1 from public.listings l join public.owner_asset_claims c on c.asset_id=l.asset_id where l.id=b.listing_id and c.owner_id=public.current_owner_id() and c.status='verified')
  into v_authorized;
  if not v_authorized then raise exception 'Authorized provider access required'; end if;
  if p_agreed_total_minor<=0 then raise exception 'Agreed total must be positive'; end if;
  if nullif(trim(p_agreement_version),'') is null then raise exception 'Agreement version is required'; end if;
  select deposit_minor,balance_minor into v_deposit,v_balance from public.calculate_booking_split(p_agreed_total_minor,25);
  select coalesce(max(version),0)+1 into v_version from public.booking_terms_snapshots where booking_request_id=b.id;
  update public.booking_terms_snapshots set status='superseded' where booking_request_id=b.id and status='offered';
  insert into public.booking_terms_snapshots(booking_request_id,version,agreed_total_minor,deposit_minor,balance_minor,price_breakdown,booking_inputs,cancellation_policy_snapshot,provider_obligations_snapshot,agreement_version,balance_due_at,service_timezone,offered_by)
  values(b.id,v_version,p_agreed_total_minor,v_deposit,v_balance,coalesce(p_price_breakdown,'{}'),coalesce(p_booking_inputs,'{}'),p_cancellation_policy,coalesce(p_provider_obligations,'{}'),trim(p_agreement_version),p_balance_due_at,coalesce(nullif(trim(p_service_timezone),''),'Africa/Dar_es_Salaam'),auth.uid()) returning * into r;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata) values(auth.uid(),'booking_terms_offered','booking_requests',b.id,jsonb_build_object('snapshot_id',r.id,'version',r.version,'total_minor',r.agreed_total_minor));
  return r;
end $$;
revoke all on function public.offer_booking_terms(uuid,bigint,jsonb,jsonb,jsonb,jsonb,text,timestamptz,text) from public;
grant execute on function public.offer_booking_terms(uuid,bigint,jsonb,jsonb,jsonb,jsonb,text,timestamptz,text) to authenticated;

create or replace function public.accept_booking_terms(p_snapshot_id uuid)
returns public.booking_terms_snapshots language plpgsql security definer set search_path=public as $$
declare r public.booking_terms_snapshots;b public.booking_requests;
begin
  select s.* into r from public.booking_terms_snapshots s join public.booking_requests x on x.id=s.booking_request_id
  where s.id=p_snapshot_id and x.customer_id=auth.uid() for update of s;
  if r.id is null or r.status<>'offered' then raise exception 'Booking terms are unavailable'; end if;
  update public.booking_terms_snapshots set status='accepted',accepted_by=auth.uid(),accepted_at=now() where id=r.id returning * into r;
  update public.booking_requests set policy_accepted_at=now(),updated_at=now() where id=r.booking_request_id;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata) values(auth.uid(),'booking_terms_accepted','booking_requests',r.booking_request_id,jsonb_build_object('snapshot_id',r.id,'version',r.version));
  return r;
end $$;
revoke all on function public.accept_booking_terms(uuid) from public;
grant execute on function public.accept_booking_terms(uuid) to authenticated;

create table if not exists public.booking_state_events (
  id bigint generated always as identity primary key,
  booking_request_id uuid not null references public.booking_requests(id) on delete restrict,
  from_status public.booking_status,
  to_status public.booking_status not null,
  actor_id uuid references public.profiles(id) on delete set null,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.booking_state_events enable row level security;
create policy booking_state_events_participant_read on public.booking_state_events for select to authenticated
using(public.is_admin() or public.is_booking_participant(booking_request_id));
create policy booking_state_events_service_insert on public.booking_state_events for insert to service_role with check(true);

create or replace function public.valid_booking_transition(p_from public.booking_status,p_to public.booking_status)
returns boolean language sql immutable set search_path=public as $$
 select p_from is null or (p_from,p_to) in (
  ('new','checking_availability'),('new','reserved'),('new','cancelled'),('new','rejected'),
  ('checking_availability','contacted'),('checking_availability','reserved'),('checking_availability','cancelled'),('checking_availability','rejected'),
  ('contacted','viewing_scheduled'),('contacted','reserved'),('contacted','cancelled'),('contacted','rejected'),
  ('viewing_scheduled','reserved'),('viewing_scheduled','cancelled'),('viewing_scheduled','rejected'),
  ('reserved','confirmed'),('reserved','cancelled'),
  ('confirmed','completed'),('confirmed','cancelled'),
  ('agent_delayed','checking_availability'),('agent_delayed','contacted'),('agent_delayed','cancelled'),
  ('no_response','checking_availability'),('no_response','cancelled')
 )
$$;
grant execute on function public.valid_booking_transition(public.booking_status,public.booking_status) to authenticated,service_role;

comment on table public.kodimali_feature_flags is 'Controlled KODIMALI 3.0 rollout flags; new financial automation is disabled until explicitly approved.';
comment on table public.booking_configurations is 'Explicit per-listing booking mode and verified booking authority. Publication alone does not grant Instant Booking.';
comment on table public.booking_terms_snapshots is 'Immutable versioned price, policy and agreement snapshot using integer TZS minor units.';
comment on table public.booking_state_events is 'Append-only authoritative booking transition audit stream.';
