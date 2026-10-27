-- KODIMALI 3.0 phase 4: structured negotiation, fulfillment evidence,
-- provider-failure protection and independently tracked cancellation outcomes.

create or replace function public.is_booking_provider(p_booking_request_id uuid,p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
 select exists(
  select 1 from public.booking_requests b
  join public.listings l on l.id=b.listing_id
  left join public.agents a on a.id=b.agent_id
  where b.id=p_booking_request_id and (
   a.profile_id=p_user_id or exists(
    select 1 from public.owner_asset_claims c join public.owner_profiles o on o.id=c.owner_id
    where c.asset_id=l.asset_id and c.status='verified' and o.profile_id=p_user_id
   )
  )
 )
$$;
grant execute on function public.is_booking_provider(uuid,uuid) to authenticated,service_role;

create table if not exists public.negotiated_booking_offers (
 id uuid primary key default gen_random_uuid(),booking_request_id uuid not null references public.booking_requests(id) on delete restrict,
 listing_id uuid not null references public.listings(id) on delete restrict,customer_id uuid not null references public.profiles(id) on delete restrict,
 provider_profile_id uuid not null references public.profiles(id) on delete restrict,version integer not null,
 agreed_total_minor bigint not null check(agreed_total_minor>0),currency text not null default 'TZS' check(currency='TZS'),
 starts_at timestamptz not null,ends_at timestamptz not null,quantity integer check(quantity is null or quantity>0),
 included_services jsonb not null default '[]'::jsonb,additional_fees jsonb not null default '[]'::jsonb,
 booking_inputs jsonb not null default '{}'::jsonb,cancellation_policy_snapshot jsonb not null,provider_obligations_snapshot jsonb not null default '{}'::jsonb,
 agreement_version text not null,expires_at timestamptz not null,status text not null default 'offered' check(status in ('draft','offered','accepted','declined','expired','superseded','converted')),
 created_at timestamptz not null default now(),accepted_at timestamptz,unique(booking_request_id,version),check(ends_at>starts_at)
);
create unique index if not exists negotiated_offer_one_live_idx on public.negotiated_booking_offers(booking_request_id) where status in ('draft','offered','accepted');
alter table public.negotiated_booking_offers enable row level security;
create policy negotiated_offer_participants_read on public.negotiated_booking_offers for select to authenticated using(customer_id=auth.uid() or provider_profile_id=auth.uid() or public.has_admin_permission('bookings.manage'));

create table if not exists public.booking_amendments (
 id uuid primary key default gen_random_uuid(),booking_request_id uuid not null references public.booking_requests(id) on delete restrict,
 previous_terms_snapshot_id uuid not null references public.booking_terms_snapshots(id) on delete restrict,new_terms_snapshot_id uuid not null references public.booking_terms_snapshots(id) on delete restrict,
 reason text not null,payment_difference_minor bigint not null default 0,status text not null default 'proposed' check(status in ('proposed','accepted','declined','settled','superseded')),
 proposed_by uuid not null references public.profiles(id) on delete restrict,accepted_by uuid references public.profiles(id),accepted_at timestamptz,created_at timestamptz not null default now()
);
alter table public.booking_amendments enable row level security;
create policy booking_amendment_participants_read on public.booking_amendments for select to authenticated using(public.is_admin() or public.is_booking_participant(booking_request_id));

create or replace function public.accept_negotiated_booking_offer(p_offer_id uuid)
returns public.booking_terms_snapshots language plpgsql security definer set search_path=public as $$
declare o public.negotiated_booking_offers;b public.booking_requests;asset uuid;v_version integer;v_deposit bigint;v_balance bigint;s public.booking_terms_snapshots;
begin
 select * into o from public.negotiated_booking_offers where id=p_offer_id and customer_id=auth.uid() for update;
 if o.id is null or o.status<>'offered' or o.expires_at<=now() then raise exception 'Negotiated offer is unavailable or expired'; end if;
 select * into b from public.booking_requests where id=o.booking_request_id for update;
 select asset_id into asset from public.listings where id=o.listing_id;
 if asset is null then raise exception 'Listing is not connected to reservable inventory'; end if;
 update public.asset_reservations r set status='expired',updated_at=now() from public.booking_requests x where r.booking_request_id=x.id and r.status='held' and x.payment_expires_at<=now();
 if exists(select 1 from public.asset_reservations r where r.asset_id=asset and r.booking_request_id<>b.id and r.status in ('held','confirmed') and r.occupied_period&&tstzrange(o.starts_at,o.ends_at,'[)')) then raise exception 'The offered period is no longer available' using errcode='23P01'; end if;
 select deposit_minor,balance_minor into v_deposit,v_balance from public.calculate_booking_split(o.agreed_total_minor,25);
 select coalesce(max(version),0)+1 into v_version from public.booking_terms_snapshots where booking_request_id=b.id;
 update public.booking_terms_snapshots set status='superseded' where booking_request_id=b.id and status='offered';
 insert into public.booking_terms_snapshots(booking_request_id,version,agreed_total_minor,deposit_minor,balance_minor,price_breakdown,booking_inputs,cancellation_policy_snapshot,provider_obligations_snapshot,agreement_version,status,offered_by,accepted_by,accepted_at)
 values(b.id,v_version,o.agreed_total_minor,v_deposit,v_balance,jsonb_build_object('negotiated_offer_id',o.id,'included_services',o.included_services,'additional_fees',o.additional_fees),o.booking_inputs,o.cancellation_policy_snapshot,o.provider_obligations_snapshot,o.agreement_version,'accepted',o.provider_profile_id,auth.uid(),now()) returning * into s;
 update public.negotiated_booking_offers set status='converted',accepted_at=now() where id=o.id;
 update public.booking_requests set requested_start_at=o.starts_at,requested_end_at=o.ends_at,policy_accepted_at=now(),updated_at=now() where id=b.id;
 insert into public.audit_logs(actor_id,action,target_table,target_id,metadata) values(auth.uid(),'negotiated_offer_converted','booking_requests',b.id,jsonb_build_object('offer_id',o.id,'snapshot_id',s.id));
 return s;
end $$;
revoke all on function public.accept_negotiated_booking_offer(uuid) from public;
grant execute on function public.accept_negotiated_booking_offer(uuid) to authenticated;

create table if not exists public.fulfillment_milestones (
 id uuid primary key default gen_random_uuid(),booking_request_id uuid not null references public.booking_requests(id) on delete restrict,
 milestone_kind text not null check(milestone_kind in ('handover','tenancy_start','vehicle_pickup','vehicle_return','venue_access','period_completed','equipment_delivery','equipment_quantity_verified','equipment_collection','professional_attendance','service_completed')),
 due_at timestamptz,status text not null default 'pending' check(status in ('pending','ready','provider_confirmed','customer_confirmed','verified','failed','disputed','waived')),
 provider_confirmed_at timestamptz,customer_confirmed_at timestamptz,verified_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(booking_request_id,milestone_kind)
);
create table if not exists public.fulfillment_evidence (
 id uuid primary key default gen_random_uuid(),milestone_id uuid references public.fulfillment_milestones(id) on delete restrict,
 incident_id uuid,uploaded_by uuid not null references public.profiles(id) on delete restrict,evidence_kind text not null check(evidence_kind in ('photo','document','message_reference','handover_code','note','system_event')),
 storage_path text,details jsonb not null default '{}'::jsonb,captured_at timestamptz not null default now(),created_at timestamptz not null default now(),
 check(storage_path is not null or details<>'{}'::jsonb)
);
create table if not exists public.booking_incidents (
 id uuid primary key default gen_random_uuid(),booking_request_id uuid not null references public.booking_requests(id) on delete restrict,
 milestone_id uuid references public.fulfillment_milestones(id) on delete set null,reported_by uuid not null references public.profiles(id) on delete restrict,
 incident_kind text not null check(incident_kind in ('asset_unavailable','access_failure','provider_absence','misrepresentation','quantity_shortfall','unsafe_or_unusable','delay','damage','other_material_failure')),
 severity text not null check(severity in ('low','medium','high','critical')),summary text not null,status text not null default 'open' check(status in ('open','investigating','corrective_action','substitution_offered','refund_review','resolved','rejected','appealed')),
 settlement_suspended boolean not null default true,assigned_to uuid references public.profiles(id),resolution text,resolved_by uuid references public.profiles(id),resolved_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.fulfillment_evidence add constraint fulfillment_evidence_incident_fkey foreign key(incident_id) references public.booking_incidents(id) on delete restrict;
create table if not exists public.booking_substitution_proposals (
 id uuid primary key default gen_random_uuid(),incident_id uuid not null references public.booking_incidents(id) on delete restrict,
 proposed_listing_id uuid references public.listings(id) on delete restrict,description text not null,price_difference_minor bigint not null default 0,
 status text not null default 'proposed' check(status in ('proposed','customer_accepted','customer_declined','expired','fulfilled','withdrawn')),
 proposed_by uuid not null references public.profiles(id) on delete restrict,expires_at timestamptz not null,responded_by uuid references public.profiles(id),responded_at timestamptz,created_at timestamptz not null default now()
);
create table if not exists public.booking_completion_windows (
 id uuid primary key default gen_random_uuid(),booking_request_id uuid not null unique references public.booking_requests(id) on delete restrict,
 completion_recorded_at timestamptz not null,dispute_deadline timestamptz not null,release_review_at timestamptz not null,status text not null default 'open' check(status in ('open','disputed','ready_for_release','closed')),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),check(dispute_deadline>=completion_recorded_at and release_review_at>=dispute_deadline)
);

alter table public.fulfillment_milestones enable row level security;alter table public.fulfillment_evidence enable row level security;
alter table public.booking_incidents enable row level security;alter table public.booking_substitution_proposals enable row level security;alter table public.booking_completion_windows enable row level security;
create policy fulfillment_participants_read on public.fulfillment_milestones for select to authenticated using(public.is_admin() or public.is_booking_participant(booking_request_id));
create policy fulfillment_evidence_participants_read on public.fulfillment_evidence for select to authenticated using(public.is_admin() or exists(select 1 from public.fulfillment_milestones m where m.id=milestone_id and public.is_booking_participant(m.booking_request_id)) or exists(select 1 from public.booking_incidents i where i.id=incident_id and public.is_booking_participant(i.booking_request_id)));
create policy incident_participants_read on public.booking_incidents for select to authenticated using(public.is_admin() or public.is_booking_participant(booking_request_id));
create policy incident_participant_insert on public.booking_incidents for insert to authenticated with check(reported_by=auth.uid() and public.is_booking_participant(booking_request_id));
create policy substitution_participants_read on public.booking_substitution_proposals for select to authenticated using(public.is_admin() or exists(select 1 from public.booking_incidents i where i.id=incident_id and public.is_booking_participant(i.booking_request_id)));
create policy completion_window_participants_read on public.booking_completion_windows for select to authenticated using(public.is_admin() or public.is_booking_participant(booking_request_id));

create or replace function public.report_booking_incident(p_booking_request_id uuid,p_incident_kind text,p_severity text,p_summary text,p_milestone_id uuid default null)
returns public.booking_incidents language plpgsql security definer set search_path=public as $$
declare r public.booking_incidents;
begin
 if not public.is_booking_participant(p_booking_request_id) then raise exception 'Booking participant access required'; end if;
 insert into public.booking_incidents(booking_request_id,milestone_id,reported_by,incident_kind,severity,summary)
 values(p_booking_request_id,p_milestone_id,auth.uid(),p_incident_kind,p_severity,trim(p_summary)) returning * into r;
 update public.provider_payables set status='on_hold',updated_at=now() where booking_request_id=p_booking_request_id and status in ('pending_fulfillment','eligible','scheduled');
 insert into public.audit_logs(actor_id,action,target_table,target_id,metadata) values(auth.uid(),'booking_incident_reported','booking_requests',p_booking_request_id,jsonb_build_object('incident_id',r.id,'kind',r.incident_kind,'severity',r.severity));
 return r;
end $$;
revoke all on function public.report_booking_incident(uuid,text,text,text,uuid) from public;
grant execute on function public.report_booking_incident(uuid,text,text,text,uuid) to authenticated;

create or replace function public.respond_booking_substitution(p_proposal_id uuid,p_accept boolean)
returns public.booking_substitution_proposals language plpgsql security definer set search_path=public as $$
declare r public.booking_substitution_proposals;customer uuid;
begin
 select s.* into r from public.booking_substitution_proposals s where s.id=p_proposal_id for update;
 select b.customer_id into customer from public.booking_incidents i join public.booking_requests b on b.id=i.booking_request_id where i.id=r.incident_id;
 if customer<>auth.uid() or r.status<>'proposed' or r.expires_at<=now() then raise exception 'Substitution proposal is unavailable'; end if;
 update public.booking_substitution_proposals set status=case when p_accept then 'customer_accepted' else 'customer_declined' end,responded_by=auth.uid(),responded_at=now() where id=r.id returning * into r;
 update public.booking_incidents set status=case when p_accept then 'corrective_action' else 'refund_review' end,updated_at=now() where id=r.incident_id;
 return r;
end $$;
revoke all on function public.respond_booking_substitution(uuid,boolean) from public;
grant execute on function public.respond_booking_substitution(uuid,boolean) to authenticated;

comment on table public.negotiated_booking_offers is 'Structured offers only; ordinary chat messages never modify booking terms.';
comment on table public.booking_incidents is 'Customer/provider protection cases that independently suspend eligible settlement while reviewed.';
