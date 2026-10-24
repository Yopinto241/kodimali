-- Complete the verified owner -> invited renter -> accepted agreement workflow.

alter table public.rental_agreements
  add column if not exists invitation_id uuid unique references public.tenant_invitations(id) on delete restrict;

create or replace function public.create_rental_agreement_from_invitation(
  p_invitation_id uuid,
  p_starts_on date,
  p_ends_on date,
  p_rent_amount_tzs numeric,
  p_rent_period text,
  p_terms jsonb default '{}'::jsonb
) returns public.rental_agreements
language plpgsql security definer set search_path=public as $$
declare
  oid uuid := public.current_owner_id();
  invitation public.tenant_invitations;
  agreement public.rental_agreements;
begin
  if oid is null then raise exception 'Verified owner access required'; end if;
  select * into invitation from public.tenant_invitations
    where id=p_invitation_id and owner_id=oid for update;
  if invitation.id is null then raise exception 'Invitation is not available to this owner'; end if;
  if invitation.status <> 'accepted' or invitation.accepted_by is null then
    raise exception 'The renter must accept the invitation first';
  end if;
  if p_starts_on < current_date then raise exception 'Start date cannot be in the past'; end if;
  if p_ends_on is not null and p_ends_on <= p_starts_on then raise exception 'End date must be after start date'; end if;
  if p_rent_amount_tzs is null or p_rent_amount_tzs < 0 then raise exception 'Rent amount is invalid'; end if;
  if p_rent_period not in ('day','week','month','year') then raise exception 'Rent period is invalid'; end if;

  insert into public.rental_agreements(
    owner_id, asset_id, tenant_id, invitation_id, starts_on, ends_on,
    rent_amount_tzs, rent_period, terms, status
  ) values (
    oid, invitation.asset_id, invitation.accepted_by, invitation.id,
    p_starts_on, p_ends_on, p_rent_amount_tzs, p_rent_period,
    coalesce(p_terms,'{}'::jsonb), 'pending_tenant'
  ) returning * into agreement;
  return agreement;
end $$;

create or replace function public.accept_rental_agreement(p_agreement_id uuid)
returns public.rental_agreements
language plpgsql security definer set search_path=public as $$
declare agreement public.rental_agreements;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into agreement from public.rental_agreements
    where id=p_agreement_id and tenant_id=auth.uid() for update;
  if agreement.id is null then raise exception 'Agreement is not available to this renter'; end if;
  if agreement.status <> 'pending_tenant' then raise exception 'Agreement is not awaiting acceptance'; end if;
  update public.rental_agreements
    set status='active', tenant_accepted_at=now(), updated_at=now()
    where id=agreement.id returning * into agreement;
  return agreement;
end $$;

revoke all on function public.create_rental_agreement_from_invitation(uuid,date,date,numeric,text,jsonb) from public, anon;
revoke all on function public.accept_rental_agreement(uuid) from public, anon;
grant execute on function public.create_rental_agreement_from_invitation(uuid,date,date,numeric,text,jsonb) to authenticated;
grant execute on function public.accept_rental_agreement(uuid) to authenticated;

