-- KODIMALI 3.0: external deals are declarations, not platform collections.
-- Restrict declarations to a party with an actual relationship to the listing
-- or referral and keep verification/admin accounting separate.

drop policy if exists external_deal_self_insert on public.external_deal_declarations;

create or replace function public.declare_external_deal(
  p_listing_id uuid,
  p_referral_submission_id uuid,
  p_other_party_id uuid,
  p_claimed_value_minor bigint,
  p_transaction_date date,
  p_evidence_paths jsonb default '[]'::jsonb,
  p_notes text default null
)
returns public.external_deal_declarations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_authorized boolean := false;
  v_result public.external_deal_declarations;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if (p_listing_id is null) = (p_referral_submission_id is null) then
    raise exception 'Choose exactly one related listing or referral';
  end if;
  if p_claimed_value_minor<0 then raise exception 'Deal value cannot be negative'; end if;
  if p_transaction_date>current_date then raise exception 'Transaction date cannot be in the future'; end if;
  if jsonb_typeof(coalesce(p_evidence_paths,'[]'::jsonb))<>'array' then
    raise exception 'Evidence paths must be an array';
  end if;

  if p_listing_id is not null then
    select public.is_admin() or exists(
      select 1 from public.listings l
      left join public.agents a on a.id=l.agent_id
      left join public.owner_asset_claims c on c.asset_id=l.asset_id and c.status='verified'
      left join public.owner_profiles o on o.id=c.owner_id
      where l.id=p_listing_id
        and (a.profile_id=auth.uid() or o.profile_id=auth.uid())
    ) into v_authorized;
  else
    select public.is_admin() or exists(
      select 1 from public.rental_information_submissions s
      left join public.agents a on a.id=s.assigned_agent_id
      where s.id=p_referral_submission_id
        and (s.contributor_id=auth.uid() or a.profile_id=auth.uid())
    ) into v_authorized;
  end if;
  if not coalesce(v_authorized,false) then
    raise exception 'You are not authorized to declare a deal for this record';
  end if;

  insert into public.external_deal_declarations(
    listing_id,referral_submission_id,declared_by,other_party_id,
    claimed_value_minor,transaction_date,evidence_paths,status,notes
  ) values(
    p_listing_id,p_referral_submission_id,auth.uid(),p_other_party_id,
    p_claimed_value_minor,p_transaction_date,coalesce(p_evidence_paths,'[]'::jsonb),
    case when jsonb_array_length(coalesce(p_evidence_paths,'[]'::jsonb))>0 then 'evidence_submitted' else 'reported' end,
    nullif(trim(p_notes),'')
  ) returning * into v_result;

  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'external_deal_declared','external_deal_declarations',v_result.id,
    jsonb_build_object('listing_id',p_listing_id,'referral_submission_id',p_referral_submission_id,'claimed_value_minor',p_claimed_value_minor));
  return v_result;
end;
$$;

revoke all on function public.declare_external_deal(uuid,uuid,uuid,bigint,date,jsonb,text)
from public, anon, authenticated;
grant execute on function public.declare_external_deal(uuid,uuid,uuid,bigint,date,jsonb,text)
to authenticated, service_role;

comment on function public.declare_external_deal(uuid,uuid,uuid,bigint,date,jsonb,text) is
'Records an authorized external deal declaration without creating fictional KODIMALI payment collection.';

create or replace function public.review_external_deal(
  p_deal_id uuid,
  p_status text,
  p_notes text default null
)
returns public.external_deal_declarations
language plpgsql
security definer
set search_path = public
as $$
declare v_result public.external_deal_declarations;
begin
  if not public.has_admin_permission('payments.manage') then
    raise exception 'Payment management permission required';
  end if;
  if p_status not in ('verified','commission_assessed','settled','rejected','disputed') then
    raise exception 'Unsupported external deal review status';
  end if;
  update public.external_deal_declarations
  set status=p_status,
      verified_by=case when p_status in ('verified','commission_assessed','settled') then auth.uid() else verified_by end,
      verified_at=case when p_status in ('verified','commission_assessed','settled') then coalesce(verified_at,now()) else verified_at end,
      notes=coalesce(nullif(trim(p_notes),''),notes),
      updated_at=now()
  where id=p_deal_id
  returning * into v_result;
  if v_result.id is null then raise exception 'External deal was not found'; end if;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'external_deal_reviewed','external_deal_declarations',v_result.id,jsonb_build_object('status',p_status,'notes',p_notes));
  return v_result;
end;
$$;

revoke all on function public.review_external_deal(uuid,text,text)
from public, anon, authenticated;
grant execute on function public.review_external_deal(uuid,text,text)
to authenticated, service_role;
