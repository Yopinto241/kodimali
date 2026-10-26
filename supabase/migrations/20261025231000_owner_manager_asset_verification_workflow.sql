create or replace function public.submit_owner_listing_claim(
  p_listing_id uuid,
  p_authority_type text,
  p_evidence_paths jsonb default '[]'::jsonb
)
returns public.owner_asset_claims
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_id uuid := public.current_owner_id();
  v_asset_id uuid;
  v_claim public.owner_asset_claims;
begin
  if v_owner_id is null then raise exception 'Verified owner or manager access required'; end if;
  if p_authority_type not in ('owner','authorized_manager') then raise exception 'Invalid authority type'; end if;
  select asset_id into v_asset_id from public.listings where id = p_listing_id;
  if v_asset_id is null then raise exception 'Listing is not connected to inventory yet'; end if;
  insert into public.owner_asset_claims(owner_id,asset_id,authority_type,evidence_paths,status)
  values(v_owner_id,v_asset_id,p_authority_type,coalesce(p_evidence_paths,'[]'::jsonb),'pending')
  on conflict(owner_id,asset_id) do update
    set authority_type=excluded.authority_type,evidence_paths=excluded.evidence_paths,
        status='pending',verified_by=null,verified_at=null,updated_at=now()
  returning * into v_claim;
  return v_claim;
end;
$$;

create or replace function public.review_owner_asset_claim(
  p_claim_id uuid,
  p_approve boolean,
  p_notes text default null
)
returns public.owner_asset_claims
language plpgsql
security definer
set search_path = public
as $$
declare v_claim public.owner_asset_claims;
begin
  if not (public.is_admin() or public.has_admin_permission('inventory.manage')) then
    raise exception 'Inventory verification permission required';
  end if;
  select * into v_claim from public.owner_asset_claims where id=p_claim_id for update;
  if v_claim.id is null or v_claim.status not in ('pending','rejected') then
    raise exception 'Asset claim is not reviewable';
  end if;
  if not exists(select 1 from public.owner_profiles where id=v_claim.owner_id and verification_status='verified') then
    raise exception 'Owner or manager identity must be verified first';
  end if;
  update public.owner_asset_claims
  set status=case when p_approve then 'verified' else 'rejected' end,
      verified_by=case when p_approve then auth.uid() else null end,
      verified_at=case when p_approve then now() else null end,
      notes=nullif(trim(p_notes),''),updated_at=now()
  where id=v_claim.id returning * into v_claim;
  if p_approve then
    update public.rental_assets
    set verification_status='verified',owner_advertising_authorized=true,
        authorization_evidence=jsonb_build_object('claim_id',v_claim.id,'authority_type',v_claim.authority_type),
        verified_by=auth.uid(),verified_at=now(),updated_at=now()
    where id=v_claim.asset_id;
    insert into public.asset_verification_history(asset_id,status,notes,evidence,verified_by)
    values(v_claim.asset_id,'verified',nullif(trim(p_notes),''),jsonb_build_object('claim_id',v_claim.id),auth.uid());
  end if;
  return v_claim;
end;
$$;

revoke all on function public.submit_owner_listing_claim(uuid,text,jsonb),public.review_owner_asset_claim(uuid,boolean,text) from public;
grant execute on function public.submit_owner_listing_claim(uuid,text,jsonb) to authenticated;
grant execute on function public.review_owner_asset_claim(uuid,boolean,text) to authenticated;
