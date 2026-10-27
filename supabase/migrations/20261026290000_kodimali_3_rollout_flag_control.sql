-- KODIMALI 3.0: audited Super Admin rollout control. This migration does not
-- enable any feature; every flag remains in its existing state.

create or replace function public.set_kodimali_feature_flag(
  p_key text,
  p_enabled boolean,
  p_approval_note text,
  p_configuration jsonb default '{}'::jsonb
)
returns public.kodimali_feature_flags
language plpgsql
security definer
set search_path = public
as $$
declare
  v_flag public.kodimali_feature_flags;
begin
  if not public.is_super_admin() then
    raise exception 'Super Admin access required';
  end if;
  if not exists(select 1 from public.kodimali_feature_flags where key=p_key) then
    raise exception 'Unknown KODIMALI rollout flag';
  end if;
  if p_enabled and length(trim(coalesce(p_approval_note,'')))<10 then
    raise exception 'A clear approval note is required before activation';
  end if;

  update public.kodimali_feature_flags
  set enabled=p_enabled,
      configuration=coalesce(p_configuration,'{}'::jsonb),
      approved_by=case when p_enabled then auth.uid() else approved_by end,
      approved_at=case when p_enabled then now() else approved_at end,
      updated_by=auth.uid(),
      updated_at=now()
  where key=p_key
  returning * into v_flag;

  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(
    auth.uid(),
    case when p_enabled then 'kodimali_feature_enabled' else 'kodimali_feature_disabled' end,
    'kodimali_feature_flags',
    null,
    jsonb_build_object(
      'key',p_key,
      'enabled',p_enabled,
      'approval_note',trim(coalesce(p_approval_note,'')),
      'configuration',coalesce(p_configuration,'{}'::jsonb)
    )
  );
  return v_flag;
end;
$$;

revoke all on function public.set_kodimali_feature_flag(text,boolean,text,jsonb)
from public, anon, authenticated;
grant execute on function public.set_kodimali_feature_flag(text,boolean,text,jsonb)
to authenticated, service_role;

comment on function public.set_kodimali_feature_flag(text,boolean,text,jsonb) is
'Audited Super Admin rollout switch. Enabling requires an explicit approval note.';
