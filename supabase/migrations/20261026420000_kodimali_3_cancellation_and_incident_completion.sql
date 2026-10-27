-- Complete cancellation dependencies and support approved partial-fulfillment
-- remedies without silently deducting provider funds.

create table if not exists public.commission_reversals (
  id uuid primary key default gen_random_uuid(),
  cancellation_case_id uuid not null references public.booking_cancellation_cases(id) on delete restrict,
  commission_obligation_id uuid not null references public.commission_obligations(id) on delete restrict,
  beneficiary_profile_id uuid not null references public.profiles(id) on delete restrict,
  kind text not null check(kind in ('agent_commission','referral_reward')),
  amount_minor bigint not null check(amount_minor>0),
  status text not null default 'pending_review' check(status in ('pending_review','offset_pending','recovered','waived','disputed')),
  resolution text,
  resolved_by uuid references public.profiles(id) on delete restrict,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(cancellation_case_id,commission_obligation_id)
);
alter table public.commission_reversals enable row level security;
create policy commission_reversals_finance_read on public.commission_reversals
for select to authenticated using(
  beneficiary_profile_id=auth.uid() or public.has_admin_permission('payments.manage')
  or public.has_admin_permission('refunds.manage')
);

create or replace function public.is_booking_provider(
  p_booking_request_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean language sql stable security definer set search_path=public as $$
  select public.has_booking_provider_permission(
    p_booking_request_id,'bookings.manage',p_user_id
  )
$$;

create or replace function public.request_booking_cancellation(
  p_booking_request_id uuid,
  p_reason text
)
returns public.booking_cancellation_cases
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.booking_requests;
  s public.booking_terms_snapshots;
  paid bigint;
  allocation record;
  r public.booking_cancellation_cases;
  party text;
begin
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'A clear cancellation reason is required'; end if;
  select * into b from public.booking_requests where id=p_booking_request_id for update;
  if b.id is null then raise exception 'Booking not found'; end if;
  if b.customer_id=auth.uid() then party:='customer';
  elsif public.has_booking_provider_permission(b.id,'bookings.manage') then party:='provider';
  elsif public.has_admin_permission('bookings.manage') then party:='admin';
  else raise exception 'Customer, controlling owner or delegated booking authority required';
  end if;
  if b.booking_status in ('completed','cancelled','rejected') then
    raise exception 'This booking cannot be cancelled from its current state';
  end if;
  select * into s from public.booking_terms_snapshots
  where booking_request_id=b.id and status='accepted';
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
          and v.is_active order by v.version desc limit 1;
      end if;
    exception when invalid_text_representation then
      raise exception 'The accepted cancellation policy reference is invalid';
    end;
    if s.cancellation_policy_version_id is not null then
      update public.booking_terms_snapshots set cancellation_policy_version_id=s.cancellation_policy_version_id where id=s.id;
    end if;
  end if;
  if s.cancellation_policy_version_id is null then
    raise exception 'An accepted versioned cancellation policy is required';
  end if;
  select coalesce(round(sum(amount_tzs)),0)::bigint into paid
  from public.booking_payment_transactions
  where booking_request_id=b.id and status='paid'
    and kind in ('reservation','deposit','balance','service_fee');
  select * into allocation from public.calculate_cancellation_allocation(
    s.cancellation_policy_version_id,paid,b.requested_start_at,now()
  );
  insert into public.booking_cancellation_cases(
    booking_request_id,requested_by,party,reason,policy_version_id,paid_minor,
    customer_refund_minor,provider_compensation_minor,platform_fee_minor,
    refund_status,provider_compensation_status,settlement_status
  ) values(
    b.id,auth.uid(),party,trim(p_reason),s.cancellation_policy_version_id,paid,
    allocation.customer_minor,allocation.provider_minor,allocation.platform_minor,
    case when allocation.customer_minor>0 then 'pending_review' else 'not_started' end,
    case when allocation.provider_minor>0 then 'eligible' else 'not_started' end,
    case when allocation.provider_minor>0 then 'on_hold' else 'not_started' end
  ) returning * into r;
  update public.booking_requests set cancellation_status='requested',updated_at=now() where id=b.id;
  update public.provider_payables set status='on_hold',updated_at=now()
  where booking_request_id=b.id and status not in ('settled','reversed');
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'booking_cancellation_requested','booking_requests',b.id,
    jsonb_build_object('case_id',r.id,'party',party,'paid_minor',paid));
  return r;
end;
$$;

create or replace function public.complete_cancellation_dependencies()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_agent_paid boolean;v_referral_paid boolean;
begin
  if new.booking_status<>'cancelled' or old.booking_status='cancelled' then return new; end if;
  update public.commission_obligations set status='reversed',updated_at=now()
  where booking_request_id=new.booking_request_id
    and status in ('pending','eligible','payable');
  insert into public.commission_reversals(
    cancellation_case_id,commission_obligation_id,beneficiary_profile_id,kind,amount_minor
  )
  select new.id,c.id,c.beneficiary_profile_id,c.kind,c.amount_minor
  from public.commission_obligations c
  where c.booking_request_id=new.booking_request_id and c.status='paid' and c.amount_minor>0
  on conflict(cancellation_case_id,commission_obligation_id) do nothing;
  select exists(select 1 from public.commission_reversals where cancellation_case_id=new.id and kind='agent_commission') into v_agent_paid;
  select exists(select 1 from public.commission_reversals where cancellation_case_id=new.id and kind='referral_reward') into v_referral_paid;
  update public.booking_cancellation_cases set
    commission_reversal_status=case
      when v_agent_paid then 'pending'
      when exists(select 1 from public.commission_obligations where booking_request_id=new.booking_request_id and kind='agent_commission' and status='reversed') then 'completed'
      else 'not_applicable' end,
    referral_adjustment_status=case
      when v_referral_paid then 'pending'
      when exists(select 1 from public.commission_obligations where booking_request_id=new.booking_request_id and kind='referral_reward' and status='reversed') then 'completed'
      else 'not_applicable' end,
    updated_at=now()
  where id=new.id;
  if new.customer_refund_minor>0 and exists(
    select 1 from public.provider_payables p
    where p.booking_request_id=new.booking_request_id and p.status='settled'
  ) and not exists(
    select 1 from public.financial_reconciliation_cases x
    where x.provider='internal_ledger' and x.provider_order_id='settled-cancellation:'||new.id::text
  ) then
    insert into public.financial_reconciliation_cases(
      provider,provider_order_id,expected_amount_minor,reason,status
    ) values(
      'internal_ledger','settled-cancellation:'||new.id::text,new.customer_refund_minor,
      'Customer refund approved after provider settlement; recovery or approved loss treatment is required','open'
    );
  end if;
  return new;
end;
$$;
drop trigger if exists complete_cancellation_dependencies on public.booking_cancellation_cases;
create trigger complete_cancellation_dependencies
after update of booking_status on public.booking_cancellation_cases
for each row execute function public.complete_cancellation_dependencies();

create or replace function public.enforce_booking_payable_recipient()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_owner_profile uuid;
begin
  if new.booking_request_id is null then return new; end if;
  select o.profile_id into v_owner_profile
  from public.booking_requests b
  join public.listings l on l.id=b.listing_id
  join public.owner_asset_claims c on c.asset_id=l.asset_id and c.status='verified'
  join public.owner_profiles o on o.id=c.owner_id and o.verification_status='verified'
  where b.id=new.booking_request_id
  order by c.verified_at desc nulls last limit 1;
  if v_owner_profile is not null then new.provider_profile_id:=v_owner_profile; end if;
  return new;
end;
$$;
drop trigger if exists enforce_booking_payable_recipient on public.provider_payables;
create trigger enforce_booking_payable_recipient before insert on public.provider_payables
for each row execute function public.enforce_booking_payable_recipient();

create or replace function public.resolve_booking_incident(
  p_incident_id uuid,
  p_resolution text,
  p_customer_refund_minor bigint default 0
)
returns public.booking_incidents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_incident public.booking_incidents;
  v_booking public.booking_requests;
  v_collected bigint;
  v_existing_refunds bigint;
begin
  if not public.has_admin_permission('disputes.manage')
     or (p_customer_refund_minor>0 and not public.has_admin_permission('refunds.manage')) then
    raise exception 'Dispute and refund permissions are required';
  end if;
  if length(trim(coalesce(p_resolution,'')))<10 then raise exception 'A clear resolution is required'; end if;
  if p_customer_refund_minor<0 then raise exception 'Refund cannot be negative'; end if;
  select * into v_incident from public.booking_incidents where id=p_incident_id for update;
  if v_incident.id is null or v_incident.status in ('resolved','rejected') then
    raise exception 'Incident is not reviewable';
  end if;
  select * into v_booking from public.booking_requests where id=v_incident.booking_request_id for update;
  select coalesce(sum(amount_minor),0) into v_collected from public.payment_intents
  where resource_type='booking_request' and resource_id=v_booking.id and status='verified_paid';
  select coalesce(sum(amount_minor),0) into v_existing_refunds from public.refund_obligations
  where booking_request_id=v_booking.id and status not in ('declined');
  if p_customer_refund_minor>v_collected-v_existing_refunds then
    raise exception 'Refund exceeds the verified unrefunded collection';
  end if;
  if p_customer_refund_minor>0 then
    insert into public.refund_obligations(
      booking_request_id,customer_id,amount_minor,reason,status,approved_by,approved_at
    ) values(
      v_booking.id,v_booking.customer_id,p_customer_refund_minor,
      'Approved partial-fulfillment remedy: '||trim(p_resolution),'approved',auth.uid(),now()
    );
  end if;
  update public.provider_payables set status='on_hold',updated_at=now()
  where booking_request_id=v_booking.id and status in ('pending_fulfillment','eligible','scheduled');
  if p_customer_refund_minor>0 and exists(
    select 1 from public.provider_payables where booking_request_id=v_booking.id and status='settled'
  ) then
    insert into public.financial_reconciliation_cases(
      provider,provider_order_id,expected_amount_minor,reason,status
    ) values(
      'internal_ledger','incident:'||v_incident.id::text,p_customer_refund_minor,
      'Partial-fulfillment refund approved after provider settlement','open'
    );
  end if;
  update public.booking_incidents set status='resolved',resolution=trim(p_resolution),
    resolved_by=auth.uid(),resolved_at=now(),settlement_suspended=p_customer_refund_minor>0,
    updated_at=now() where id=v_incident.id returning * into v_incident;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'booking_incident_resolved','booking_incidents',v_incident.id,
    jsonb_build_object('booking_request_id',v_booking.id,'refund_minor',p_customer_refund_minor,'resolution',trim(p_resolution)));
  return v_incident;
end;
$$;

revoke all on function public.resolve_booking_incident(uuid,text,bigint) from public,anon,authenticated;
grant execute on function public.resolve_booking_incident(uuid,text,bigint) to authenticated,service_role;
revoke all on function public.complete_cancellation_dependencies(),public.enforce_booking_payable_recipient() from public,anon,authenticated;

comment on table public.commission_reversals is
'Paid commissions and rewards require an explicit recovery, offset, waiver or dispute decision; no silent deduction is performed.';
