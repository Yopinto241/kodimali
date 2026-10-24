-- KODIMALI 2.0: private public referrals, centralized inventory and safe reservations.
-- Additive only. Financial collection remains disabled until explicitly configured.

create extension if not exists btree_gist;

insert into public.admin_role_definitions(id,name,description,permissions,rank)
values ('information_admin','Information Admin','Private lead verification, inventory intake and referral administration.',
  '["information.manage","inventory.manage","referrals.manage","disputes.manage"]'::jsonb,75)
on conflict(id) do update set name=excluded.name,description=excluded.description,
  permissions=excluded.permissions,rank=excluded.rank,is_active=true;

create or replace function public.is_information_admin(check_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select public.has_admin_permission('information.manage',check_user)
$$;
revoke all on function public.is_information_admin(uuid) from public;
grant execute on function public.is_information_admin(uuid) to authenticated,service_role;

create table public.rental_information_submissions(
  id uuid primary key default gen_random_uuid(),
  reference text not null unique default ('TA-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
  contributor_id uuid not null references public.profiles(id) on delete restrict,
  category public.listing_category not null,
  location_id uuid references public.locations(id) on delete restrict,
  location_description text not null check(length(trim(location_description)) between 3 and 500),
  description text not null check(length(trim(description)) between 10 and 4000),
  approximate_rent numeric(14,2) check(approximate_rent is null or approximate_rent>=0),
  price_period public.price_period,
  available_from timestamptz,
  information_source text not null check(length(trim(information_source)) between 2 and 200),
  category_details jsonb not null default '{}'::jsonb check(jsonb_typeof(category_details)='object'),
  photo_paths jsonb not null default '[]'::jsonb check(jsonb_typeof(photo_paths)='array' and jsonb_array_length(photo_paths)<=8),
  photo_permission_confirmed boolean not null default false,
  owner_name text,
  owner_phone text,
  owner_contact_authorized boolean not null default false,
  status text not null default 'submitted' check(status in
    ('submitted','triage','duplicate_review','contacting_owner','field_verification','verified','publication_review','published','ineligible','closed')),
  eligibility_status text not null default 'pending' check(eligibility_status in ('pending','eligible','ineligible','paid')),
  assigned_information_admin_id uuid references public.profiles(id) on delete set null,
  assigned_agent_id uuid references public.agents(id) on delete set null,
  possible_duplicate_of uuid references public.rental_information_submissions(id) on delete set null,
  linked_asset_id uuid,
  next_follow_up_at timestamptz,
  submitted_at timestamptz not null default now(),updated_at timestamptz not null default now(),
  check(owner_contact_authorized or (owner_name is null and owner_phone is null))
);

create table public.information_follow_ups(
 id uuid primary key default gen_random_uuid(),submission_id uuid not null references public.rental_information_submissions(id) on delete cascade,
 kind text not null check(kind in ('note','call','message','evidence','deadline','status_change','assignment')),
 summary text not null check(length(trim(summary)) between 1 and 2000),evidence_paths jsonb not null default '[]'::jsonb,
 due_at timestamptz,completed_at timestamptz,created_by uuid not null references public.profiles(id),created_at timestamptz not null default now()
);

create table public.rental_assets(
 id uuid primary key default gen_random_uuid(),asset_code text not null unique default ('AS-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
 category public.listing_category not null,location_id uuid references public.locations(id) on delete restrict,
 fingerprint text not null,display_name text not null,private_address text,owner_id uuid references public.owners(id) on delete set null,
 source_submission_id uuid references public.rental_information_submissions(id) on delete set null,
 verification_status text not null default 'pending' check(verification_status in ('pending','field_verification','verified','rejected','suspended')),
 owner_advertising_authorized boolean not null default false,authorization_evidence jsonb not null default '{}'::jsonb,
 verified_by uuid references public.profiles(id),verified_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(category,fingerprint),check(verification_status<>'verified' or (owner_advertising_authorized and verified_at is not null))
);
alter table public.rental_information_submissions add constraint rental_information_linked_asset_fkey foreign key(linked_asset_id) references public.rental_assets(id) on delete set null;

create table public.asset_verification_history(
 id uuid primary key default gen_random_uuid(),asset_id uuid not null references public.rental_assets(id) on delete cascade,
 status text not null,notes text,evidence jsonb not null default '{}'::jsonb,verified_by uuid not null references public.profiles(id),created_at timestamptz not null default now()
);

alter table public.listings add column if not exists asset_id uuid references public.rental_assets(id) on delete restrict;
create index if not exists idx_listings_asset on public.listings(asset_id) where asset_id is not null;

create table public.referral_agreements(
 id uuid primary key default gen_random_uuid(),submission_id uuid not null unique references public.rental_information_submissions(id) on delete restrict,
 reward_type text not null check(reward_type in ('fixed','percentage')),fixed_amount_tzs numeric(14,2),percentage_rate numeric(7,4),
 eligible_fee_basis text not null default 'collected_service_fee',terms text not null,terms_version integer not null default 1,
 agreed_at timestamptz not null default now(),agreed_by uuid not null references public.profiles(id),
 check((reward_type='fixed' and fixed_amount_tzs>0 and percentage_rate is null) or (reward_type='percentage' and percentage_rate>0 and percentage_rate<=100 and fixed_amount_tzs is null))
);

create table public.referral_rewards(
 id uuid primary key default gen_random_uuid(),agreement_id uuid not null references public.referral_agreements(id) on delete restrict,
 booking_request_id uuid not null references public.booking_requests(id) on delete restrict,responsible_agent_id uuid references public.agents(id) on delete set null,
 eligible_fee_collected_tzs numeric(14,2) not null check(eligible_fee_collected_tzs>=0),reward_amount_tzs numeric(14,2) not null check(reward_amount_tzs>0),
 status text not null default 'pending_review' check(status in ('pending_review','eligible','on_hold','approved','paid','rejected')),
 approved_by uuid references public.profiles(id),approved_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(agreement_id,booking_request_id)
);
create table public.referral_payouts(
 id uuid primary key default gen_random_uuid(),reward_id uuid not null unique references public.referral_rewards(id) on delete restrict,
 amount_tzs numeric(14,2) not null check(amount_tzs>0),transaction_reference text not null unique,payment_method text not null,
 paid_by uuid not null references public.profiles(id),paid_at timestamptz not null default now(),notes text
);

create table public.booking_policies(
 id uuid primary key default gen_random_uuid(),category public.listing_category,version integer not null,title text not null,body text not null,
 fee_configuration jsonb not null default '{}'::jsonb,cancellation_configuration jsonb not null default '{}'::jsonb,
 active_from timestamptz not null,active_until timestamptz,is_active boolean not null default false,created_by uuid references public.profiles(id),created_at timestamptz not null default now(),
 unique(category,version)
);
alter table public.booking_requests add column if not exists booking_kind text not null default 'viewing' check(booking_kind in ('viewing','reservation'));
alter table public.booking_requests add column if not exists policy_id uuid references public.booking_policies(id) on delete restrict;
alter table public.booking_requests add column if not exists policy_accepted_at timestamptz;
alter table public.booking_requests add column if not exists payment_expires_at timestamptz;

create table public.asset_reservations(
 id uuid primary key default gen_random_uuid(),asset_id uuid not null references public.rental_assets(id) on delete restrict,
 booking_request_id uuid not null unique references public.booking_requests(id) on delete restrict,
 occupied_period tstzrange not null,status text not null check(status in ('held','confirmed','completed','cancelled','expired')),
 created_by uuid references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(not isempty(occupied_period) and lower_inc(occupied_period) and not upper_inc(occupied_period)),
 exclude using gist(asset_id with =,occupied_period with &&) where(status in ('held','confirmed'))
);

create table public.booking_payment_transactions(
 id uuid primary key default gen_random_uuid(),booking_request_id uuid not null references public.booking_requests(id) on delete restrict,
 provider text not null,provider_reference text not null,kind text not null check(kind in ('reservation','deposit','balance','service_fee','refund')),
 amount_tzs numeric(14,2) not null check(amount_tzs>0),status text not null check(status in ('created','authorized','paid','failed','cancelled','refunded')),
 verified_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(provider,provider_reference)
);
create table public.payment_webhook_events(
 id uuid primary key default gen_random_uuid(),provider text not null,provider_event_id text not null,payload_digest text not null,
 signature_verified boolean not null default false,processed_at timestamptz,processing_error text,received_at timestamptz not null default now(),unique(provider,provider_event_id)
);
create table public.booking_disputes(
 id uuid primary key default gen_random_uuid(),booking_request_id uuid not null references public.booking_requests(id) on delete restrict,
 opened_by uuid not null references public.profiles(id),reason text not null,details text,status text not null default 'open' check(status in ('open','investigating','resolved','rejected')),
 resolution text,resolved_by uuid references public.profiles(id),resolved_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);

create index idx_information_submission_contributor on public.rental_information_submissions(contributor_id,submitted_at desc);
create index idx_information_work_queue on public.rental_information_submissions(status,next_follow_up_at);
create index idx_asset_reservations_asset_period on public.asset_reservations using gist(asset_id,occupied_period);

alter table public.rental_information_submissions enable row level security;
alter table public.information_follow_ups enable row level security;
alter table public.rental_assets enable row level security;
alter table public.asset_verification_history enable row level security;
alter table public.referral_agreements enable row level security;
alter table public.referral_rewards enable row level security;
alter table public.referral_payouts enable row level security;
alter table public.booking_policies enable row level security;
alter table public.asset_reservations enable row level security;
alter table public.booking_payment_transactions enable row level security;
alter table public.payment_webhook_events enable row level security;
alter table public.booking_disputes enable row level security;

create policy information_contributor_read on public.rental_information_submissions for select to authenticated using(contributor_id=auth.uid() or public.is_information_admin());
create policy information_admin_all on public.rental_information_submissions for all to authenticated using(public.is_information_admin()) with check(public.is_information_admin());
create policy followups_admin_only on public.information_follow_ups for all to authenticated using(public.is_information_admin()) with check(public.is_information_admin());
create policy assets_staff_read on public.rental_assets for select to authenticated using(public.has_admin_permission('inventory.manage') or public.is_admin());
create policy assets_inventory_manage on public.rental_assets for all to authenticated using(public.has_admin_permission('inventory.manage')) with check(public.has_admin_permission('inventory.manage'));
create policy verification_staff_only on public.asset_verification_history for all to authenticated using(public.has_admin_permission('inventory.manage')) with check(public.has_admin_permission('inventory.manage'));
create policy agreements_contributor_read on public.referral_agreements for select to authenticated using(public.is_information_admin() or exists(select 1 from public.rental_information_submissions s where s.id=submission_id and s.contributor_id=auth.uid()));
create policy agreements_admin_manage on public.referral_agreements for all to authenticated using(public.has_admin_permission('referrals.manage')) with check(public.has_admin_permission('referrals.manage'));
create policy rewards_contributor_read on public.referral_rewards for select to authenticated using(public.has_admin_permission('referrals.manage') or exists(select 1 from public.referral_agreements a join public.rental_information_submissions s on s.id=a.submission_id where a.id=agreement_id and s.contributor_id=auth.uid()));
create policy rewards_admin_manage on public.referral_rewards for all to authenticated using(public.has_admin_permission('referrals.manage')) with check(public.has_admin_permission('referrals.manage'));
create policy payouts_contributor_read on public.referral_payouts for select to authenticated using(public.has_admin_permission('referrals.manage') or exists(select 1 from public.referral_rewards r join public.referral_agreements a on a.id=r.agreement_id join public.rental_information_submissions s on s.id=a.submission_id where r.id=reward_id and s.contributor_id=auth.uid()));
create policy policies_authenticated_read on public.booking_policies for select to authenticated using(is_active or public.is_admin());
create policy policies_admin_manage on public.booking_policies for all to authenticated using(public.has_admin_permission('bookings.manage')) with check(public.has_admin_permission('bookings.manage'));
create policy reservations_participant_read on public.asset_reservations for select to authenticated using(public.is_admin() or public.is_booking_participant(booking_request_id));
create policy payment_participant_read on public.booking_payment_transactions for select to authenticated using(public.is_admin() or public.is_booking_participant(booking_request_id));
create policy webhook_service_only on public.payment_webhook_events for all to service_role using(true) with check(true);
create policy disputes_participant_read on public.booking_disputes for select to authenticated using(opened_by=auth.uid() or public.is_admin() or public.is_booking_participant(booking_request_id));

create or replace function public.submit_rental_information(p_category public.listing_category,p_location_id uuid,p_location_description text,p_description text,p_approximate_rent numeric,p_price_period public.price_period,p_available_from timestamptz,p_information_source text,p_category_details jsonb default '{}'::jsonb,p_photo_paths jsonb default '[]'::jsonb,p_photo_permission_confirmed boolean default false,p_owner_name text default null,p_owner_phone text default null,p_owner_contact_authorized boolean default false)
returns public.rental_information_submissions language plpgsql security definer set search_path=public as $$ declare v_row public.rental_information_submissions; begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_owner_contact_authorized=false and (nullif(trim(p_owner_name),'') is not null or nullif(trim(p_owner_phone),'') is not null) then raise exception 'Owner contact authorization is required'; end if;
 insert into public.rental_information_submissions(contributor_id,category,location_id,location_description,description,approximate_rent,price_period,available_from,information_source,category_details,photo_paths,photo_permission_confirmed,owner_name,owner_phone,owner_contact_authorized)
 values(auth.uid(),p_category,p_location_id,trim(p_location_description),trim(p_description),p_approximate_rent,p_price_period,p_available_from,trim(p_information_source),coalesce(p_category_details,'{}'),case when p_photo_permission_confirmed then coalesce(p_photo_paths,'[]') else '[]' end,p_photo_permission_confirmed,nullif(trim(p_owner_name),''),nullif(trim(p_owner_phone),''),p_owner_contact_authorized) returning * into v_row;
 insert into public.audit_logs(actor_id,action,target_table,target_id,metadata) values(auth.uid(),'rental_information_submitted','rental_information_submissions',v_row.id,jsonb_build_object('reference',v_row.reference)); return v_row; end $$;
revoke all on function public.submit_rental_information(public.listing_category,uuid,text,text,numeric,public.price_period,timestamptz,text,jsonb,jsonb,boolean,text,text,boolean) from public;
grant execute on function public.submit_rental_information(public.listing_category,uuid,text,text,numeric,public.price_period,timestamptz,text,jsonb,jsonb,boolean,text,text,boolean) to authenticated;

create or replace function public.confirm_asset_reservation(p_booking_request_id uuid)
returns public.asset_reservations language plpgsql security definer set search_path=public as $$ declare v_booking public.booking_requests; v_asset uuid; v_payment_ok boolean; v_row public.asset_reservations; begin
 if not public.has_admin_permission('bookings.manage') then raise exception 'Booking management permission required'; end if;
 select * into v_booking from public.booking_requests where id=p_booking_request_id for update;
 select asset_id into v_asset from public.listings where id=v_booking.listing_id;
 if v_asset is null then raise exception 'Listing is not linked to centralized inventory'; end if;
 if v_booking.booking_kind='reservation' then select exists(select 1 from public.booking_payment_transactions where booking_request_id=v_booking.id and kind='reservation' and status='paid' and verified_at is not null) into v_payment_ok; if not v_payment_ok then raise exception 'Verified server-side payment is required'; end if; end if;
 insert into public.asset_reservations(asset_id,booking_request_id,occupied_period,status,created_by) values(v_asset,v_booking.id,tstzrange(v_booking.requested_start_at,v_booking.requested_end_at,'[)'),'confirmed',auth.uid()) returning * into v_row;
 update public.booking_requests set booking_status='confirmed',updated_at=now() where id=v_booking.id; return v_row;
exception when exclusion_violation then raise exception 'Asset is already reserved for an overlapping period' using errcode='23P01'; end $$;
revoke all on function public.confirm_asset_reservation(uuid) from public;
grant execute on function public.confirm_asset_reservation(uuid) to authenticated,service_role;

create or replace function public.record_referral_payout(p_reward_id uuid,p_transaction_reference text,p_payment_method text,p_notes text default null)
returns public.referral_payouts language plpgsql security definer set search_path=public as $$ declare v_reward public.referral_rewards; v_row public.referral_payouts; begin
 if not public.has_admin_permission('referrals.manage') then raise exception 'Referral permission required'; end if;
 select * into v_reward from public.referral_rewards where id=p_reward_id for update;
 if v_reward.status<>'approved' then raise exception 'Reward must be approved and free of holds'; end if;
 if exists(select 1 from public.booking_disputes where booking_request_id=v_reward.booking_request_id and status in ('open','investigating')) then raise exception 'Outstanding dispute blocks payout'; end if;
 insert into public.referral_payouts(reward_id,amount_tzs,transaction_reference,payment_method,paid_by,notes) values(v_reward.id,v_reward.reward_amount_tzs,trim(p_transaction_reference),trim(p_payment_method),auth.uid(),p_notes) returning * into v_row;
 update public.referral_rewards set status='paid',updated_at=now() where id=v_reward.id;
 update public.rental_information_submissions s set eligibility_status='paid',updated_at=now() from public.referral_agreements a where a.id=v_reward.agreement_id and s.id=a.submission_id;
 return v_row; end $$;
revoke all on function public.record_referral_payout(uuid,text,text,text) from public;
grant execute on function public.record_referral_payout(uuid,text,text,text) to authenticated;

create trigger set_information_submission_updated_at before update on public.rental_information_submissions for each row execute function public.set_updated_at();
create trigger set_rental_asset_updated_at before update on public.rental_assets for each row execute function public.set_updated_at();
create trigger set_referral_reward_updated_at before update on public.referral_rewards for each row execute function public.set_updated_at();
create trigger set_asset_reservation_updated_at before update on public.asset_reservations for each row execute function public.set_updated_at();
create trigger set_booking_dispute_updated_at before update on public.booking_disputes for each row execute function public.set_updated_at();

comment on table public.rental_information_submissions is 'Private customer leads; owner contacts are never publicly selectable.';
comment on table public.rental_assets is 'Canonical physical inventory independent from agent advertisements.';
comment on table public.referral_payouts is 'Admin-recorded manual payouts only; not a stored-value wallet.';
