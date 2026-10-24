-- KODIMALI owner workspace and owner-approved booking foundation.
-- Additive only. Payment collection and payouts remain disabled.

create table if not exists public.owner_profiles (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles(id) on delete cascade,
  owner_type text not null check (owner_type in ('individual','vehicle_owner','venue_owner','equipment_owner','authorized_manager')),
  display_name text not null,
  phone_number text not null,
  verification_status text not null default 'pending' check (verification_status in ('pending','under_review','verified','rejected','suspended')),
  verification_notes text,
  verified_by uuid references public.profiles(id), verified_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.owner_applications (
  id uuid primary key default gen_random_uuid(), applicant_id uuid not null references public.profiles(id) on delete cascade,
  owner_type text not null check (owner_type in ('individual','vehicle_owner','venue_owner','equipment_owner','authorized_manager')),
  legal_name text not null, phone_number text not null, authorization_summary text not null,
  document_paths jsonb not null default '[]'::jsonb,
  status text not null default 'submitted' check(status in ('submitted','under_review','approved','rejected')),
  reviewed_by uuid references public.profiles(id), reviewed_at timestamptz, review_notes text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists owner_application_one_open on public.owner_applications(applicant_id) where status in ('submitted','under_review');

create table if not exists public.owner_asset_claims (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.owner_profiles(id) on delete cascade,
  asset_id uuid not null references public.rental_assets(id) on delete restrict,
  authority_type text not null check(authority_type in ('owner','authorized_manager')),
  evidence_paths jsonb not null default '[]'::jsonb,
  status text not null default 'pending' check(status in ('pending','verified','rejected','revoked')),
  verified_by uuid references public.profiles(id), verified_at timestamptz, notes text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(owner_id,asset_id)
);

alter table public.booking_policies add column if not exists owner_id uuid references public.owner_profiles(id) on delete cascade;
alter table public.booking_policies add column if not exists asset_id uuid references public.rental_assets(id) on delete cascade;
alter table public.booking_policies add column if not exists approval_mode text not null default 'manual' check(approval_mode in ('manual','automatic'));
alter table public.booking_policies add column if not exists minimum_notice_hours integer not null default 2 check(minimum_notice_hours>=0);
alter table public.booking_policies add column if not exists owner_accepted_at timestamptz;
alter table public.booking_policies add column if not exists owner_accepted_by uuid references public.profiles(id);

create table if not exists public.owner_booking_agreement_versions (
  id uuid primary key default gen_random_uuid(), version integer not null unique, title text not null, body text not null,
  is_active boolean not null default false, effective_from timestamptz not null, created_by uuid references public.profiles(id), created_at timestamptz not null default now()
);
create table if not exists public.owner_booking_agreement_acceptances (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.owner_profiles(id) on delete cascade,
  agreement_version_id uuid not null references public.owner_booking_agreement_versions(id) on delete restrict,
  accepted_by uuid not null references public.profiles(id), accepted_at timestamptz not null default now(), ip_metadata jsonb not null default '{}'::jsonb,
  unique(owner_id,agreement_version_id)
);
insert into public.owner_booking_agreement_versions(version,title,body,is_active,effective_from)
values(1,'KODIMALI Owner Booking Agreement','I confirm my authority over each connected asset, maintain accurate prices and availability, respond to booking requests, honor accepted reservations and handover obligations, and follow the stated cancellation, refund, commission, settlement and dispute rules. KODIMALI does not operate a wallet or escrow. Collection and settlement begin only after the required provider, contractual and legal approvals.',true,now())
on conflict(version) do nothing;

create table if not exists public.tenant_invitations (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.owner_profiles(id) on delete cascade,
  asset_id uuid not null references public.rental_assets(id) on delete restrict, email text, phone_number text,
  token_hash text not null unique, status text not null default 'pending' check(status in ('pending','accepted','declined','expired','cancelled')),
  invited_by uuid not null references public.profiles(id), accepted_by uuid references public.profiles(id), expires_at timestamptz not null,
  accepted_at timestamptz, created_at timestamptz not null default now(), check(email is not null or phone_number is not null)
);
create table if not exists public.rental_agreements (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.owner_profiles(id) on delete restrict,
  asset_id uuid not null references public.rental_assets(id) on delete restrict, tenant_id uuid not null references public.profiles(id) on delete restrict,
  starts_on date not null, ends_on date, rent_amount_tzs numeric(14,2) not null check(rent_amount_tzs>=0), rent_period text not null,
  terms jsonb not null default '{}'::jsonb, status text not null default 'draft' check(status in ('draft','pending_tenant','active','ended','cancelled')),
  tenant_accepted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), check(ends_on is null or ends_on>starts_on)
);
create table if not exists public.tenant_move_out_notices (
  id uuid primary key default gen_random_uuid(), agreement_id uuid not null references public.rental_agreements(id) on delete restrict,
  tenant_id uuid not null references public.profiles(id) on delete restrict, intended_move_out_on date not null, reason text,
  status text not null default 'submitted' check(status in ('submitted','acknowledged','withdrawn','completed')),
  referral_submission_id uuid references public.rental_information_submissions(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.owner_statement_entries (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.owner_profiles(id) on delete restrict,
  booking_request_id uuid references public.booking_requests(id) on delete restrict,
  entry_type text not null check(entry_type in ('customer_payment','owner_entitlement','service_fee','agent_commission','referral_reward','refund_liability','settlement_adjustment','payout')),
  amount_tzs numeric(14,2) not null, status text not null check(status in ('pending','confirmed','refundable','payable','settled','void')),
  external_reference text, description text not null, occurred_at timestamptz not null default now(), created_at timestamptz not null default now()
);

alter table public.booking_requests add column if not exists owner_approval_status text not null default 'not_required' check(owner_approval_status in ('not_required','pending','approved','declined','expired'));
alter table public.booking_requests add column if not exists owner_approved_by uuid references public.profiles(id);
alter table public.booking_requests add column if not exists owner_approved_at timestamptz;
alter table public.booking_requests add column if not exists owner_response_deadline timestamptz;
alter table public.booking_requests add column if not exists cancellation_status text not null default 'none' check(cancellation_status in ('none','requested','approved','declined','completed'));
alter table public.booking_requests add column if not exists refund_status text not null default 'not_applicable' check(refund_status in ('not_applicable','pending_review','approved','processing','refunded','declined'));

alter table public.owner_profiles enable row level security; alter table public.owner_applications enable row level security;
alter table public.owner_asset_claims enable row level security; alter table public.owner_booking_agreement_versions enable row level security;
alter table public.owner_booking_agreement_acceptances enable row level security; alter table public.tenant_invitations enable row level security;
alter table public.rental_agreements enable row level security; alter table public.tenant_move_out_notices enable row level security;
alter table public.owner_statement_entries enable row level security;

create or replace function public.current_owner_id() returns uuid language sql stable security definer set search_path=public as $$ select id from public.owner_profiles where profile_id=auth.uid() and verification_status='verified' limit 1 $$;
create policy owner_profiles_self_admin_read on public.owner_profiles for select to authenticated using(profile_id=auth.uid() or public.is_admin());
create policy owner_applications_self_read on public.owner_applications for select to authenticated using(applicant_id=auth.uid() or public.is_admin());
create policy owner_applications_self_insert on public.owner_applications for insert to authenticated with check(applicant_id=auth.uid() and status='submitted');
create policy owner_claims_owner_admin on public.owner_asset_claims for select to authenticated using(owner_id=public.current_owner_id() or public.is_admin());
create policy owner_claims_owner_insert on public.owner_asset_claims for insert to authenticated with check(owner_id=public.current_owner_id() and status='pending');
create policy owner_policies_manage on public.booking_policies for all to authenticated using(owner_id=public.current_owner_id()) with check(owner_id=public.current_owner_id());
create policy owner_agreement_versions_read on public.owner_booking_agreement_versions for select to authenticated using(is_active or public.is_admin());
create policy owner_acceptances_self_read on public.owner_booking_agreement_acceptances for select to authenticated using(owner_id=public.current_owner_id() or public.is_admin());
create policy tenant_invitations_participants on public.tenant_invitations for select to authenticated using(owner_id=public.current_owner_id() or accepted_by=auth.uid() or public.is_admin());
create policy rental_agreements_participants on public.rental_agreements for select to authenticated using(owner_id=public.current_owner_id() or tenant_id=auth.uid() or public.is_admin());
create policy move_out_participants on public.tenant_move_out_notices for select to authenticated using(tenant_id=auth.uid() or exists(select 1 from public.rental_agreements a where a.id=agreement_id and a.owner_id=public.current_owner_id()) or public.is_admin());
create policy statements_owner_admin_read on public.owner_statement_entries for select to authenticated using(owner_id=public.current_owner_id() or public.is_admin());
create policy booking_requests_owner_read on public.booking_requests for select to authenticated using(exists(select 1 from public.listings l join public.owner_asset_claims c on c.asset_id=l.asset_id where l.id=booking_requests.listing_id and c.owner_id=public.current_owner_id() and c.status='verified'));

create or replace function public.apply_for_owner_access(p_owner_type text,p_legal_name text,p_phone_number text,p_authorization_summary text,p_document_paths jsonb default '[]') returns public.owner_applications language plpgsql security definer set search_path=public as $$ declare r public.owner_applications; begin if auth.uid() is null then raise exception 'Authentication required'; end if; insert into public.owner_applications(applicant_id,owner_type,legal_name,phone_number,authorization_summary,document_paths) values(auth.uid(),p_owner_type,trim(p_legal_name),trim(p_phone_number),trim(p_authorization_summary),coalesce(p_document_paths,'[]')) returning * into r; return r; end $$;

create or replace function public.review_owner_application(p_application_id uuid,p_approve boolean,p_notes text default null) returns public.owner_applications language plpgsql security definer set search_path=public as $$ declare a public.owner_applications; begin if not (public.is_admin() or public.has_admin_permission('inventory.manage')) then raise exception 'Owner verification permission required'; end if; select * into a from public.owner_applications where id=p_application_id for update; if a.id is null or a.status not in ('submitted','under_review') then raise exception 'Application is not reviewable'; end if; update public.owner_applications set status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now(),review_notes=p_notes,updated_at=now() where id=a.id returning * into a; if p_approve then insert into public.owner_profiles(profile_id,owner_type,display_name,phone_number,verification_status,verified_by,verified_at) values(a.applicant_id,a.owner_type,a.legal_name,a.phone_number,'verified',auth.uid(),now()) on conflict(profile_id) do update set owner_type=excluded.owner_type,display_name=excluded.display_name,phone_number=excluded.phone_number,verification_status='verified',verified_by=auth.uid(),verified_at=now(),updated_at=now(); insert into public.user_roles(profile_id,role) values(a.applicant_id,'owner') on conflict do nothing; end if; return a; end $$;

create or replace function public.accept_owner_booking_agreement(p_agreement_version_id uuid) returns public.owner_booking_agreement_acceptances language plpgsql security definer set search_path=public as $$ declare oid uuid:=public.current_owner_id(); r public.owner_booking_agreement_acceptances; begin if oid is null then raise exception 'Verified owner access required'; end if; if not exists(select 1 from public.owner_booking_agreement_versions where id=p_agreement_version_id and is_active) then raise exception 'Agreement version is not active'; end if; insert into public.owner_booking_agreement_acceptances(owner_id,agreement_version_id,accepted_by) values(oid,p_agreement_version_id,auth.uid()) on conflict(owner_id,agreement_version_id) do update set accepted_at=now(),accepted_by=auth.uid() returning * into r; return r; end $$;

create or replace function public.owner_respond_to_booking(p_booking_request_id uuid,p_approve boolean) returns public.booking_requests language plpgsql security definer set search_path=public as $$ declare b public.booking_requests; oid uuid:=public.current_owner_id(); aid uuid; begin if oid is null then raise exception 'Verified owner access required'; end if; select br.* into b from public.booking_requests br join public.listings l on l.id=br.listing_id join public.owner_asset_claims c on c.asset_id=l.asset_id and c.owner_id=oid and c.status='verified' where br.id=p_booking_request_id for update; if b.id is null then raise exception 'Booking not available to this owner'; end if; if b.owner_approval_status<>'pending' then raise exception 'Booking is not awaiting owner approval'; end if; if b.owner_response_deadline is not null and b.owner_response_deadline<now() then raise exception 'Owner approval deadline expired'; end if; if p_approve then if not exists(select 1 from public.owner_booking_agreement_acceptances a join public.owner_booking_agreement_versions v on v.id=a.agreement_version_id where a.owner_id=oid and v.is_active) then raise exception 'Accept the active owner booking agreement first'; end if; select l.asset_id into aid from public.listings l where l.id=b.listing_id; if exists(select 1 from public.asset_reservations r where r.asset_id=aid and r.status in ('held','confirmed') and r.occupied_period && tstzrange(b.requested_start_at,b.requested_end_at,'[)')) then raise exception 'Asset is already reserved for this period' using errcode='23P01'; end if; end if; update public.booking_requests set owner_approval_status=case when p_approve then 'approved' else 'declined' end,owner_approved_by=auth.uid(),owner_approved_at=now(),updated_at=now() where id=b.id returning * into b; return b; end $$;

create or replace function public.invite_tenant(p_asset_id uuid,p_email text default null,p_phone_number text default null) returns jsonb language plpgsql security definer set search_path=public as $$ declare oid uuid:=public.current_owner_id(); raw_token text:=encode(gen_random_bytes(24),'hex'); r public.tenant_invitations; begin if oid is null then raise exception 'Verified owner access required'; end if; if not exists(select 1 from public.owner_asset_claims where owner_id=oid and asset_id=p_asset_id and status='verified') then raise exception 'Verified asset control required'; end if; insert into public.tenant_invitations(owner_id,asset_id,email,phone_number,token_hash,invited_by,expires_at) values(oid,p_asset_id,nullif(lower(trim(p_email)),''),nullif(trim(p_phone_number),''),encode(digest(raw_token,'sha256'),'hex'),auth.uid(),now()+interval '7 days') returning * into r; return jsonb_build_object('id',r.id,'token',raw_token,'expires_at',r.expires_at); end $$;

create or replace function public.accept_tenant_invitation(p_token text) returns public.tenant_invitations language plpgsql security definer set search_path=public as $$ declare r public.tenant_invitations; begin if auth.uid() is null then raise exception 'Authentication required'; end if; select * into r from public.tenant_invitations where token_hash=encode(digest(trim(p_token),'sha256'),'hex') for update; if r.id is null or r.status<>'pending' or r.expires_at<=now() then raise exception 'Invitation is invalid or expired'; end if; update public.tenant_invitations set status='accepted',accepted_by=auth.uid(),accepted_at=now() where id=r.id returning * into r; return r; end $$;

create or replace function public.submit_move_out_notice(p_agreement_id uuid,p_intended_move_out_on date,p_reason text default null) returns public.tenant_move_out_notices language plpgsql security definer set search_path=public as $$ declare a public.rental_agreements;r public.tenant_move_out_notices;begin select * into a from public.rental_agreements where id=p_agreement_id and tenant_id=auth.uid() and status='active';if a.id is null then raise exception 'Active rental agreement required';end if;if p_intended_move_out_on<=current_date then raise exception 'Move-out date must be in the future';end if;insert into public.tenant_move_out_notices(agreement_id,tenant_id,intended_move_out_on,reason)values(a.id,auth.uid(),p_intended_move_out_on,nullif(trim(p_reason),''))returning * into r;return r;end $$;

create or replace function public.prepare_owner_booking_approval() returns trigger language plpgsql security definer set search_path=public as $$ begin if new.booking_kind='reservation' and exists(select 1 from public.listings l join public.owner_asset_claims c on c.asset_id=l.asset_id and c.status='verified' where l.id=new.listing_id) then new.owner_approval_status:='pending';new.owner_response_deadline:=coalesce(new.owner_response_deadline,now()+interval '24 hours');end if;return new;end $$;
drop trigger if exists prepare_owner_booking_approval on public.booking_requests;
create trigger prepare_owner_booking_approval before insert or update of booking_kind,listing_id on public.booking_requests for each row execute function public.prepare_owner_booking_approval();

revoke all on function public.current_owner_id(),public.apply_for_owner_access(text,text,text,text,jsonb),public.review_owner_application(uuid,boolean,text),public.accept_owner_booking_agreement(uuid),public.owner_respond_to_booking(uuid,boolean),public.invite_tenant(uuid,text,text),public.accept_tenant_invitation(text),public.submit_move_out_notice(uuid,date,text) from public;
grant execute on function public.current_owner_id(),public.apply_for_owner_access(text,text,text,text,jsonb),public.review_owner_application(uuid,boolean,text),public.accept_owner_booking_agreement(uuid),public.owner_respond_to_booking(uuid,boolean),public.invite_tenant(uuid,text,text),public.accept_tenant_invitation(text),public.submit_move_out_notice(uuid,date,text) to authenticated;

create trigger set_owner_profile_updated_at before update on public.owner_profiles for each row execute function public.set_updated_at();
create trigger set_owner_application_updated_at before update on public.owner_applications for each row execute function public.set_updated_at();
create trigger set_owner_claim_updated_at before update on public.owner_asset_claims for each row execute function public.set_updated_at();
create trigger set_rental_agreement_updated_at before update on public.rental_agreements for each row execute function public.set_updated_at();
create trigger set_move_out_notice_updated_at before update on public.tenant_move_out_notices for each row execute function public.set_updated_at();

comment on table public.owner_statement_entries is 'Accounting ledger only; never a wallet, escrow balance, or authorization to transmit funds.';
