-- Existing production function definitions, without production records.
CREATE OR REPLACE FUNCTION public.protect_agent_verification_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

begin

  if not public.is_admin(auth.uid()) then

    if new.profile_id is distinct from old.profile_id

       or new.verification_status is distinct from old.verification_status

       or new.verified_at is distinct from old.verified_at

       or new.admin_notes is distinct from old.admin_notes

       or new.average_response_minutes is distinct from old.average_response_minutes

    then

      raise exception 'Only an admin can change agent verification fields';

    end if;

  end if;



  return new;

end;

$function$;
CREATE OR REPLACE FUNCTION public.guard_agent_account_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' then
    new.display_name := coalesce(
      nullif(btrim(new.display_name), ''),
      nullif(btrim(new.business_name), ''),
      'Agent'
    );
    new.phone_number := nullif(btrim(new.phone_number), '');
    new.contact_email := nullif(lower(btrim(new.contact_email)), '');
    new.nida_number := nullif(upper(btrim(new.nida_number)), '');
    new.profile_photo_path := nullif(btrim(new.profile_photo_path), '');

    if public.is_admin(auth.uid()) then
      new.account_status := coalesce(
        new.account_status,
        'inactive'::public.agent_account_status
      );
      if new.account_status = 'active'::public.agent_account_status then
        new.activated_at := coalesce(new.activated_at, timezone('utc', now()));
        new.deactivated_at := null;
        new.deactivation_reason := null;
      else
        new.activated_at := null;
      end if;
      return new;
    end if;

    new.account_status := 'inactive'::public.agent_account_status;
    new.activated_at := null;
    new.deactivated_at := null;
    new.deactivation_reason := null;
    new.verification_status := coalesce(
      new.verification_status,
      'pending'::public.agent_verification_status
    );
    new.verified_at := null;
    new.admin_notes := null;
    new.average_response_minutes := null;
    return new;
  end if;

  new.display_name := coalesce(
    nullif(btrim(new.display_name), ''),
    nullif(btrim(old.display_name), ''),
    nullif(btrim(old.business_name), ''),
    'Agent'
  );
  new.phone_number := nullif(btrim(new.phone_number), '');
  new.contact_email := nullif(lower(btrim(new.contact_email)), '');
  new.nida_number := nullif(upper(btrim(new.nida_number)), '');
  new.profile_photo_path := nullif(btrim(new.profile_photo_path), '');

  if public.is_admin(auth.uid()) then
    if new.account_status = 'active'::public.agent_account_status then
      new.activated_at := coalesce(new.activated_at, old.activated_at, timezone('utc', now()));
      new.deactivated_at := null;
      new.deactivation_reason := null;
    else
      new.activated_at := null;
      new.deactivated_at := coalesce(new.deactivated_at, timezone('utc', now()));
    end if;
    return new;
  end if;

  if old.profile_id is distinct from auth.uid() then
    raise exception 'Agents can update only their own safe profile fields';
  end if;

  if old.account_status <> 'active'::public.agent_account_status then
    raise exception 'Inactive or suspended agents cannot update agent records';
  end if;

  if new.profile_id is distinct from old.profile_id
    or new.account_status is distinct from old.account_status
    or new.activated_at is distinct from old.activated_at
    or new.deactivated_at is distinct from old.deactivated_at
    or new.deactivation_reason is distinct from old.deactivation_reason
    or new.verification_status is distinct from old.verification_status
    or new.verified_at is distinct from old.verified_at
    or new.admin_notes is distinct from old.admin_notes
    or new.average_response_minutes is distinct from old.average_response_minutes
    or new.nida_number is distinct from old.nida_number
  then
    raise exception 'Agents cannot update protected agent-account fields';
  end if;

  new.profile_id := old.profile_id;
  new.account_status := old.account_status;
  new.activated_at := old.activated_at;
  new.deactivated_at := old.deactivated_at;
  new.deactivation_reason := old.deactivation_reason;
  new.verification_status := old.verification_status;
  new.verified_at := old.verified_at;
  new.admin_notes := old.admin_notes;
  new.average_response_minutes := old.average_response_minutes;
  new.nida_number := old.nida_number;

  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION public.assign_admin_role(p_user_id uuid, p_role_id text, p_assign boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 if not public.is_super_admin() then raise exception 'Only a Super Admin can assign administrative roles'; end if;
 if not exists(select 1 from public.admin_role_definitions where id=p_role_id and is_active) then raise exception 'Unknown admin role'; end if;
 if p_assign then
  insert into public.admin_role_assignments(user_id,role_id,assigned_by) values(p_user_id,p_role_id,auth.uid()) on conflict(user_id,role_id) do update set assigned_by=auth.uid(),assigned_at=now();
  insert into public.user_roles(profile_id,role) values(p_user_id,'admin') on conflict do nothing;
 else
  if p_user_id=auth.uid() and p_role_id='super_admin' and (select count(*) from public.admin_role_assignments where role_id='super_admin')<=1 then raise exception 'The final Super Admin cannot remove their own role'; end if;
  delete from public.admin_role_assignments where user_id=p_user_id and role_id=p_role_id;
 end if;
 insert into public.audit_logs(actor_id,action,target_table,target_id,metadata) values(auth.uid(),case when p_assign then 'admin_role_assigned' else 'admin_role_removed' end,'profiles',p_user_id,jsonb_build_object('role_id',p_role_id));
end $function$;
