-- A marketplace owner must never inherit platform-administrator authority.
-- Platform administration is granted only through admin_role_assignments.

create or replace function public.is_super_admin(check_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select check_user is not null
    and exists (
      select 1
      from public.admin_role_assignments
      where user_id = check_user
        and role_id = 'super_admin'
    );
$$;

create or replace function public.review_owner_application(
  p_application_id uuid,
  p_approve boolean,
  p_notes text default null
)
returns public.owner_applications
language plpgsql
security definer
set search_path = public
as $$
declare
  application public.owner_applications;
begin
  if auth.uid() is null
     or not coalesce(
       public.is_admin(auth.uid())
       or public.has_admin_permission('inventory.manage', auth.uid()),
       false
     ) then
    raise exception 'Owner verification permission required';
  end if;

  select * into application
  from public.owner_applications
  where id = p_application_id
  for update;

  if application.id is null
     or application.status not in ('submitted', 'under_review') then
    raise exception 'Application is not reviewable';
  end if;

  update public.owner_applications
  set status = case when p_approve then 'approved' else 'rejected' end,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      review_notes = nullif(trim(p_notes), ''),
      updated_at = now()
  where id = application.id
  returning * into application;

  if p_approve then
    insert into public.owner_profiles(
      profile_id, owner_type, display_name, phone_number,
      verification_status, verified_by, verified_at
    ) values (
      application.applicant_id, application.owner_type,
      application.legal_name, application.phone_number,
      'verified', auth.uid(), now()
    )
    on conflict(profile_id) do update
    set owner_type = excluded.owner_type,
        display_name = excluded.display_name,
        phone_number = excluded.phone_number,
        verification_status = 'verified',
        verified_by = auth.uid(),
        verified_at = now(),
        updated_at = now();

    insert into public.user_roles(profile_id, role)
    values(application.applicant_id, 'owner')
    on conflict do nothing;
  end if;

  return application;
end;
$$;

revoke all on function public.is_super_admin(uuid) from public, anon;
grant execute on function public.is_super_admin(uuid) to authenticated, service_role;
revoke all on function public.review_owner_application(uuid, boolean, text) from public, anon;
grant execute on function public.review_owner_application(uuid, boolean, text) to authenticated, service_role;

