-- KODIMALI 3.0: permissioned review of provider/internal discrepancies.
-- Resolving a case records the operational decision only; it never edits a
-- posted journal or invents a correcting balance.

create or replace function public.review_financial_reconciliation(
  p_case_id uuid,
  p_status text,
  p_resolution text
)
returns public.financial_reconciliation_cases
language plpgsql
security definer
set search_path = public
as $$
declare v_case public.financial_reconciliation_cases;
begin
  if not public.has_admin_permission('payments.manage') then
    raise exception 'Payment management permission required';
  end if;
  if p_status not in ('investigating','resolved','written_off') then
    raise exception 'Unsupported reconciliation status';
  end if;
  if length(trim(coalesce(p_resolution,'')))<10 then
    raise exception 'A clear reconciliation note is required';
  end if;
  select * into v_case from public.financial_reconciliation_cases
  where id=p_case_id for update;
  if v_case.id is null then raise exception 'Reconciliation case not found'; end if;
  if v_case.status in ('resolved','written_off') then
    raise exception 'Closed reconciliation cases are immutable';
  end if;
  update public.financial_reconciliation_cases
  set status=p_status,
      resolution=trim(p_resolution),
      resolved_by=case when p_status in ('resolved','written_off') then auth.uid() else null end,
      resolved_at=case when p_status in ('resolved','written_off') then now() else null end,
      updated_at=now()
  where id=v_case.id returning * into v_case;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'financial_reconciliation_reviewed','financial_reconciliation_cases',v_case.id,
    jsonb_build_object('status',p_status,'resolution',trim(p_resolution)));
  return v_case;
end;
$$;

revoke all on function public.review_financial_reconciliation(uuid,text,text)
from public,anon,authenticated;
grant execute on function public.review_financial_reconciliation(uuid,text,text)
to authenticated,service_role;

comment on function public.review_financial_reconciliation(uuid,text,text) is
'Audited operational review only; any accounting correction requires a separate append-only journal.';

