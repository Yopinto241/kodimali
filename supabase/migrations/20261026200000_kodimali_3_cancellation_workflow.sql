-- KODIMALI 3.0 phase 5: cancellation is separate from refund, compensation,
-- commission, inventory and settlement state. No automatic money movement.

alter table public.booking_terms_snapshots
 add column if not exists cancellation_policy_version_id uuid references public.cancellation_policy_versions(id) on delete restrict;

create table if not exists public.booking_cancellation_cases (
 id uuid primary key default gen_random_uuid(),booking_request_id uuid not null references public.booking_requests(id) on delete restrict,
 requested_by uuid not null references public.profiles(id) on delete restrict,party text not null check(party in ('customer','provider','admin')),
 reason text not null,policy_version_id uuid not null references public.cancellation_policy_versions(id) on delete restrict,
 paid_minor bigint not null check(paid_minor>=0),customer_refund_minor bigint not null check(customer_refund_minor>=0),
 provider_compensation_minor bigint not null check(provider_compensation_minor>=0),platform_fee_minor bigint not null check(platform_fee_minor>=0),
 booking_status text not null default 'requested' check(booking_status in ('requested','approved','declined','cancelled')),
 refund_status text not null default 'not_started' check(refund_status in ('not_started','pending_review','approved','processing','refunded','partially_refunded','declined')),
 provider_compensation_status text not null default 'not_started' check(provider_compensation_status in ('not_started','eligible','on_hold','scheduled','settled','reversed')),
 commission_reversal_status text not null default 'not_applicable' check(commission_reversal_status in ('not_applicable','pending','completed')),
 referral_adjustment_status text not null default 'not_applicable' check(referral_adjustment_status in ('not_applicable','pending','completed')),
 inventory_release_status text not null default 'pending' check(inventory_release_status in ('pending','released','retained')),
 settlement_status text not null default 'not_started' check(settlement_status in ('not_started','on_hold','eligible','scheduled','settled')),
 reviewed_by uuid references public.profiles(id),reviewed_at timestamptz,resolution_notes text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(customer_refund_minor+provider_compensation_minor+platform_fee_minor=paid_minor)
);
create unique index if not exists booking_cancellation_one_open_idx on public.booking_cancellation_cases(booking_request_id) where booking_status in ('requested','approved');
alter table public.booking_cancellation_cases enable row level security;
create policy cancellation_case_participants_read on public.booking_cancellation_cases for select to authenticated using(public.is_admin() or public.is_booking_participant(booking_request_id));

create or replace function public.request_booking_cancellation(p_booking_request_id uuid,p_reason text)
returns public.booking_cancellation_cases language plpgsql security definer set search_path=public as $$
declare b public.booking_requests;s public.booking_terms_snapshots;paid bigint;allocation record;r public.booking_cancellation_cases;party text;
begin
 select * into b from public.booking_requests where id=p_booking_request_id for update;
 if b.id is null or not public.is_booking_participant(b.id) then raise exception 'Booking participant access required'; end if;
 if b.booking_status in ('completed','cancelled','rejected') then raise exception 'This booking cannot be cancelled from its current state'; end if;
 select * into s from public.booking_terms_snapshots where booking_request_id=b.id and status='accepted';
 if s.id is null then raise exception 'Accepted booking terms are required'; end if;
 if s.cancellation_policy_version_id is null then
  begin
   if nullif(s.cancellation_policy_snapshot->>'policy_version_id','') is not null then
    select id into s.cancellation_policy_version_id from public.cancellation_policy_versions
    where id=(s.cancellation_policy_snapshot->>'policy_version_id')::uuid;
   elsif nullif(s.cancellation_policy_snapshot->>'code','') is not null then
    select v.id into s.cancellation_policy_version_id from public.cancellation_policy_versions v
    where v.code=s.cancellation_policy_snapshot->>'code'
      and v.version=coalesce(nullif(s.cancellation_policy_snapshot->>'version','')::integer,v.version)
      and v.is_active=true order by v.version desc limit 1;
   end if;
  exception when invalid_text_representation then
   raise exception 'The accepted cancellation policy reference is invalid';
  end;
  if s.cancellation_policy_version_id is not null then
   update public.booking_terms_snapshots set cancellation_policy_version_id=s.cancellation_policy_version_id where id=s.id;
  end if;
 end if;
 if s.cancellation_policy_version_id is null then raise exception 'An accepted versioned cancellation policy is required'; end if;
 select coalesce(round(sum(amount_tzs)),0)::bigint into paid from public.booking_payment_transactions where booking_request_id=b.id and status='paid' and kind in ('reservation','deposit','balance','service_fee');
 select * into allocation from public.calculate_cancellation_allocation(s.cancellation_policy_version_id,paid,b.requested_start_at,now());
 party:=case when b.customer_id=auth.uid() then 'customer' when public.is_booking_provider(b.id) then 'provider' else 'admin' end;
 insert into public.booking_cancellation_cases(booking_request_id,requested_by,party,reason,policy_version_id,paid_minor,customer_refund_minor,provider_compensation_minor,platform_fee_minor,refund_status,provider_compensation_status,settlement_status)
 values(b.id,auth.uid(),party,trim(p_reason),s.cancellation_policy_version_id,paid,allocation.customer_minor,allocation.provider_minor,allocation.platform_minor,case when allocation.customer_minor>0 then 'pending_review' else 'not_started' end,case when allocation.provider_minor>0 then 'eligible' else 'not_started' end,case when allocation.provider_minor>0 then 'on_hold' else 'not_started' end) returning * into r;
 update public.booking_requests set cancellation_status='requested',updated_at=now() where id=b.id;
 update public.provider_payables set status='on_hold',updated_at=now() where booking_request_id=b.id and status not in ('settled','reversed');
 insert into public.audit_logs(actor_id,action,target_table,target_id,metadata) values(auth.uid(),'booking_cancellation_requested','booking_requests',b.id,jsonb_build_object('case_id',r.id,'paid_minor',paid));
 return r;
end $$;
revoke all on function public.request_booking_cancellation(uuid,text) from public;
grant execute on function public.request_booking_cancellation(uuid,text) to authenticated;

create or replace function public.review_booking_cancellation(p_case_id uuid,p_approve boolean,p_notes text default null)
returns public.booking_cancellation_cases language plpgsql security definer set search_path=public as $$
declare r public.booking_cancellation_cases;b public.booking_requests;provider_profile uuid;
begin
 if not(public.has_admin_permission('refunds.manage') or public.has_admin_permission('bookings.manage')) then raise exception 'Cancellation review permission required'; end if;
 select * into r from public.booking_cancellation_cases where id=p_case_id for update;
 if r.id is null or r.booking_status<>'requested' then raise exception 'Cancellation case is not reviewable'; end if;
 select * into b from public.booking_requests where id=r.booking_request_id for update;
 if not p_approve then
  update public.booking_cancellation_cases set booking_status='declined',refund_status=case when customer_refund_minor>0 then 'declined' else refund_status end,provider_compensation_status='not_started',settlement_status='not_started',reviewed_by=auth.uid(),reviewed_at=now(),resolution_notes=p_notes,updated_at=now() where id=r.id returning * into r;
  update public.booking_requests set cancellation_status='declined',updated_at=now() where id=b.id;
  return r;
 end if;
 select a.profile_id into provider_profile from public.agents a where a.id=b.agent_id;
 update public.booking_cancellation_cases set booking_status='cancelled',refund_status=case when customer_refund_minor>0 then 'approved' else 'not_started' end,provider_compensation_status=case when provider_compensation_minor>0 then 'eligible' else 'not_started' end,inventory_release_status='released',settlement_status=case when provider_compensation_minor>0 then 'eligible' else 'not_started' end,reviewed_by=auth.uid(),reviewed_at=now(),resolution_notes=p_notes,updated_at=now() where id=r.id returning * into r;
 update public.booking_requests set booking_status='cancelled',cancellation_status='completed',refund_status=case when r.customer_refund_minor>0 then 'approved' else 'not_applicable' end,updated_at=now() where id=b.id;
 update public.asset_reservations set status='cancelled',updated_at=now() where booking_request_id=b.id and status in ('held','confirmed');
 if r.customer_refund_minor>0 then insert into public.refund_obligations(booking_request_id,customer_id,amount_minor,reason,status,approved_by,approved_at) values(b.id,b.customer_id,r.customer_refund_minor,'Approved booking cancellation','approved',auth.uid(),now()); end if;
 if r.provider_compensation_minor>0 and provider_profile is not null then insert into public.provider_payables(booking_request_id,provider_profile_id,amount_minor,status,eligible_at) values(b.id,provider_profile,r.provider_compensation_minor,'eligible',now()); end if;
 update public.commission_obligations set status='reversed',updated_at=now() where booking_request_id=b.id and status not in ('paid','reversed');
 insert into public.audit_logs(actor_id,action,target_table,target_id,metadata) values(auth.uid(),'booking_cancellation_reviewed','booking_requests',b.id,jsonb_build_object('case_id',r.id,'approved',true,'refund_minor',r.customer_refund_minor,'provider_minor',r.provider_compensation_minor,'platform_minor',r.platform_fee_minor));
 return r;
end $$;
revoke all on function public.review_booking_cancellation(uuid,boolean,text) from public;
grant execute on function public.review_booking_cancellation(uuid,boolean,text) to authenticated;

comment on table public.booking_cancellation_cases is 'Cancellation, refund, compensation, commission, inventory and settlement outcomes are tracked independently.';
