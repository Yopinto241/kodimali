-- Supervisor candidates use ordinary agent registration; only Super Admin promotes.
-- Enforce this on role assignments too, so the general role editor cannot bypass it.
create function public.guard_supervisor_agent_registration() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if new.role_id='supervisor' then
   if not public.is_super_admin() then
     raise exception 'Only Super Admin can appoint supervisors' using errcode='42501';
   end if;
   -- Preserve existing appointments, including deactivation/reactivation.
   if not exists(select 1 from public.admin_role_assignments where user_id=new.user_id and role_id='supervisor') then
     perform 1 from public.agents where profile_id=new.user_id for update;
     if not found then
       raise exception 'Register as an agent before becoming a supervisor' using errcode='23514';
     end if;
     if exists(select 1 from public.agents where profile_id=new.user_id and supervisor_id is not null) then
       raise exception 'Unassign this agent from their current supervisor before promotion' using errcode='23514';
     end if;
   end if;
 end if;
 return new;
end $$;
revoke all on function public.guard_supervisor_agent_registration() from public,anon,authenticated;
create trigger guard_supervisor_agent_registration before insert or update of role_id,user_id
on public.admin_role_assignments for each row execute function public.guard_supervisor_agent_registration();
notify pgrst, 'reload schema';
