-- KODIMALI 3.0: an agent receives operational authority only through an
-- explicit, revocable delegation from a verified controlling owner.

create table if not exists public.asset_agent_delegations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.owner_profiles(id) on delete restrict,
  asset_id uuid not null references public.rental_assets(id) on delete restrict,
  agent_id uuid not null references public.agents(id) on delete restrict,
  scopes text[] not null default array['bookings.manage','availability.manage','fulfillment.manage','customers.communicate']::text[],
  status text not null default 'active' check(status in ('active','revoked','expired')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  granted_by uuid not null references public.profiles(id) on delete restrict,
  revoked_by uuid references public.profiles(id) on delete restrict,
  revoked_at timestamptz,
  revocation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(cardinality(scopes)>0),
  check(scopes <@ array['bookings.manage','availability.manage','fulfillment.manage','customers.communicate']::text[]),
  check(ends_at is null or ends_at>starts_at),
  check(status<>'revoked' or (revoked_by is not null and revoked_at is not null))
);
create unique index if not exists asset_agent_one_active_delegation_idx
on public.asset_agent_delegations(asset_id,agent_id) where status='active';
create index if not exists asset_agent_delegations_agent_idx
on public.asset_agent_delegations(agent_id,status,ends_at);

alter table public.asset_agent_delegations enable row level security;
create policy asset_agent_delegations_participant_read
on public.asset_agent_delegations for select to authenticated
using(
  owner_id=public.current_owner_id()
  or exists(select 1 from public.agents a where a.id=agent_id and a.profile_id=auth.uid())
  or public.has_admin_permission('bookings.manage')
);

create or replace function public.has_asset_agent_permission(
  p_asset_id uuid,
  p_permission text,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.asset_agent_delegations d
    join public.agents a on a.id=d.agent_id
    join public.owner_asset_claims c on c.owner_id=d.owner_id
      and c.asset_id=d.asset_id and c.status='verified'
    join public.owner_profiles o on o.id=d.owner_id and o.verification_status='verified'
    where d.asset_id=p_asset_id and a.profile_id=p_user_id
      and a.verification_status='approved' and a.account_status='active'
      and d.status='active' and d.starts_at<=now()
      and (d.ends_at is null or d.ends_at>now())
      and p_permission=any(d.scopes)
  )
$$;

create or replace function public.has_booking_provider_permission(
  p_booking_request_id uuid,
  p_permission text,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin(p_user_id)
    or exists(
      select 1 from public.booking_requests b
      join public.listings l on l.id=b.listing_id
      join public.owner_asset_claims c on c.asset_id=l.asset_id and c.status='verified'
      join public.owner_profiles o on o.id=c.owner_id and o.verification_status='verified'
      where b.id=p_booking_request_id and o.profile_id=p_user_id
    )
    or exists(
      select 1 from public.booking_requests b
      join public.listings l on l.id=b.listing_id
      where b.id=p_booking_request_id
        and public.has_asset_agent_permission(l.asset_id,p_permission,p_user_id)
    )
$$;

create or replace function public.grant_asset_agent_delegation(
  p_asset_id uuid,
  p_agent_id uuid,
  p_scopes text[] default array['bookings.manage','availability.manage','fulfillment.manage','customers.communicate']::text[],
  p_ends_at timestamptz default null
)
returns public.asset_agent_delegations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner public.owner_profiles;
  v_result public.asset_agent_delegations;
begin
  select * into v_owner from public.owner_profiles
  where profile_id=auth.uid() and verification_status='verified';
  if v_owner.id is null or not exists(
    select 1 from public.owner_asset_claims where owner_id=v_owner.id
      and asset_id=p_asset_id and status='verified'
  ) then raise exception 'Verified control of this asset is required'; end if;
  if not exists(select 1 from public.agents where id=p_agent_id
    and verification_status='approved' and account_status='active') then
    raise exception 'Choose an active verified agent';
  end if;
  if coalesce(cardinality(p_scopes),0)=0 or not (
    p_scopes <@ array['bookings.manage','availability.manage','fulfillment.manage','customers.communicate']::text[]
  ) then raise exception 'Unsupported delegation scope'; end if;
  if p_ends_at is not null and p_ends_at<=now() then raise exception 'Delegation end must be in the future'; end if;
  insert into public.asset_agent_delegations(
    owner_id,asset_id,agent_id,scopes,status,starts_at,ends_at,granted_by
  ) values(v_owner.id,p_asset_id,p_agent_id,p_scopes,'active',now(),p_ends_at,auth.uid())
  on conflict(asset_id,agent_id) where status='active' do update set
    scopes=excluded.scopes,ends_at=excluded.ends_at,updated_at=now()
  returning * into v_result;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'asset_agent_delegation_granted','asset_agent_delegations',v_result.id,
    jsonb_build_object('asset_id',p_asset_id,'agent_id',p_agent_id,'scopes',p_scopes,'ends_at',p_ends_at));
  return v_result;
end;
$$;

create or replace function public.revoke_asset_agent_delegation(
  p_delegation_id uuid,
  p_reason text
)
returns public.asset_agent_delegations
language plpgsql
security definer
set search_path = public
as $$
declare v_result public.asset_agent_delegations;
begin
  select d.* into v_result from public.asset_agent_delegations d
  where d.id=p_delegation_id and d.status='active' for update;
  if v_result.id is null then raise exception 'Active delegation not found'; end if;
  if not (
    public.has_admin_permission('bookings.manage')
    or exists(select 1 from public.owner_profiles o where o.id=v_result.owner_id
      and o.profile_id=auth.uid() and o.verification_status='verified')
  ) then raise exception 'Delegation owner access required'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Revocation reason is required'; end if;
  update public.asset_agent_delegations set status='revoked',revoked_by=auth.uid(),
    revoked_at=now(),revocation_reason=trim(p_reason),updated_at=now()
  where id=v_result.id returning * into v_result;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'asset_agent_delegation_revoked','asset_agent_delegations',v_result.id,
    jsonb_build_object('asset_id',v_result.asset_id,'agent_id',v_result.agent_id,'reason',p_reason));
  return v_result;
end;
$$;

-- Keep historical participant readability, but require explicit authority for
-- new financial terms and fulfillment actions.
create or replace function public.offer_booking_terms(
  p_booking_request_id uuid,p_agreed_total_minor bigint,p_price_breakdown jsonb,
  p_booking_inputs jsonb,p_cancellation_policy jsonb,p_provider_obligations jsonb,
  p_agreement_version text,p_balance_due_at timestamptz default null,p_service_timezone text default 'Africa/Dar_es_Salaam'
) returns public.booking_terms_snapshots language plpgsql security definer set search_path=public as $$
declare b public.booking_requests;v_version integer;v_deposit bigint;v_balance bigint;r public.booking_terms_snapshots;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into b from public.booking_requests where id=p_booking_request_id for update;
  if b.id is null then raise exception 'Booking was not found'; end if;
  if not public.has_booking_provider_permission(b.id,'bookings.manage') then
    raise exception 'Explicit owner or delegated booking authority required';
  end if;
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

create or replace function public.confirm_provider_fulfillment_milestone(p_milestone_id uuid)
returns public.fulfillment_milestones language plpgsql security definer set search_path=public as $$
declare v_milestone public.fulfillment_milestones;
begin
  select * into v_milestone from public.fulfillment_milestones where id=p_milestone_id for update;
  if v_milestone.id is null then raise exception 'Fulfillment milestone not found'; end if;
  if not public.has_booking_provider_permission(v_milestone.booking_request_id,'fulfillment.manage') then
    raise exception 'Explicit owner or delegated fulfillment authority required';
  end if;
  if v_milestone.status in ('verified','failed','disputed','waived') then
    raise exception 'This milestone can no longer be provider-confirmed';
  end if;
  update public.fulfillment_milestones set status='provider_confirmed',
    provider_confirmed_at=coalesce(provider_confirmed_at,now()),updated_at=now()
  where id=p_milestone_id returning * into v_milestone;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'fulfillment_milestone_provider_confirmed','fulfillment_milestones',p_milestone_id,
    jsonb_build_object('booking_request_id',v_milestone.booking_request_id,'milestone_kind',v_milestone.milestone_kind));
  return v_milestone;
end;
$$;

revoke all on function public.has_asset_agent_permission(uuid,text,uuid),public.has_booking_provider_permission(uuid,text,uuid) from public;
grant execute on function public.has_asset_agent_permission(uuid,text,uuid),public.has_booking_provider_permission(uuid,text,uuid) to authenticated,service_role;
revoke all on function public.grant_asset_agent_delegation(uuid,uuid,text[],timestamptz),public.revoke_asset_agent_delegation(uuid,text) from public,anon,authenticated;
grant execute on function public.grant_asset_agent_delegation(uuid,uuid,text[],timestamptz),public.revoke_asset_agent_delegation(uuid,text) to authenticated,service_role;

comment on table public.asset_agent_delegations is
'Explicit, scoped and revocable owner authority for a verified agent; listing authorship never creates this authority.';
