-- One territory per supervisor; many supervisors may operate in the same place.
-- An agent has one owner column, so teams cannot share an agent.
create table public.supervisor_territories(
 supervisor_id uuid primary key references public.profiles(id) on delete cascade,
 location_id uuid not null references public.locations(id) on delete restrict,
 is_active boolean not null default true,
 assigned_by uuid references public.profiles(id), updated_at timestamptz not null default now()
);
alter table public.agents add column supervisor_id uuid references public.profiles(id) on delete restrict;
create index agents_supervisor_id_idx on public.agents(supervisor_id);
alter table public.supervisor_territories enable row level security;
grant select on public.supervisor_territories to authenticated;
revoke insert,update,delete on public.supervisor_territories from authenticated,anon;

create or replace function public.is_scoped_supervisor(check_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
 select not public.is_super_admin(check_user) and (exists(
  select 1 from public.admin_role_assignments where user_id=check_user and role_id='supervisor')
  or exists(select 1 from public.supervisor_territories where supervisor_id=check_user))
$$;

-- Supervisor staff must never inherit the old unrestricted admin policies,
-- including when their role or territory is temporarily inactive.
create or replace function public.is_admin(check_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
 select coalesce(current_setting('request.jwt.claim.role',true)='service_role',false)
 or coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role'='service_role',false)
 or (exists(select 1 from public.user_roles where profile_id=check_user and role='admin')
     and not public.is_scoped_supervisor(check_user))
$$;

create or replace function public.has_admin_permission(p_permission text,check_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
 select public.is_super_admin(check_user) or
 (case when public.is_scoped_supervisor(check_user) then
   p_permission='agents.manage' and exists(select 1 from public.supervisor_territories t
     join public.admin_role_assignments a on a.user_id=t.supervisor_id and a.role_id='supervisor'
     join public.admin_role_definitions r on r.id=a.role_id and r.is_active
     where t.supervisor_id=check_user and t.is_active)
 else exists(select 1 from public.admin_role_assignments a join public.admin_role_definitions r on r.id=a.role_id
   where a.user_id=check_user and r.is_active and (r.permissions ? p_permission or r.permissions ? '*')) end)
$$;

create or replace function public.get_my_admin_permissions() returns jsonb
language sql stable security definer set search_path=public as $$
 select case when public.is_super_admin() then '["*"]'::jsonb
 when public.is_scoped_supervisor() then '["agents.manage","supervisor.scoped"]'::jsonb
 else coalesce((select jsonb_agg(distinct permission) from public.admin_role_assignments a
 join public.admin_role_definitions r on r.id=a.role_id cross join lateral jsonb_array_elements_text(r.permissions) permission
 where a.user_id=auth.uid() and r.is_active),'[]'::jsonb) end
$$;

create function public.supervisor_location_contains(p_supervisor_id uuid,p_location_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
 with recursive ancestors as (
 select id,parent_id from public.locations where id=p_location_id and is_active
 union select l.id,l.parent_id from public.locations l join ancestors a on a.parent_id=l.id where l.is_active
 ) select exists(select 1 from public.supervisor_territories t join ancestors a on a.id=t.location_id
 where t.supervisor_id=p_supervisor_id and t.is_active)
$$;

create function public.can_manage_supervised_agent(p_agent_id uuid,check_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_admin_permission('agents.manage',check_user) and
 (not public.is_scoped_supervisor(check_user) or exists(select 1 from public.agents a
 where a.id=p_agent_id and a.supervisor_id=check_user and public.supervisor_location_contains(check_user,a.location_id)))
$$;

create policy supervisor_territory_read on public.supervisor_territories for select to authenticated
using(supervisor_id=auth.uid() or public.is_super_admin());
drop policy if exists agents_admin_all on public.agents;
create policy agents_admin_all on public.agents for all to authenticated
using(public.has_admin_permission('agents.manage') and not public.is_scoped_supervisor())
with check(public.has_admin_permission('agents.manage') and not public.is_scoped_supervisor());
create policy supervisor_agents_read on public.agents for select to authenticated
using(public.is_scoped_supervisor() and public.can_manage_supervised_agent(id));
create policy supervisor_exclusive_agents on public.agents as restrictive for all to authenticated
using(not public.is_scoped_supervisor() or public.can_manage_supervised_agent(id))
with check(not public.is_scoped_supervisor() or public.can_manage_supervised_agent(id));
create policy supervisor_profiles_read on public.profiles for select to authenticated
using(public.is_scoped_supervisor() and exists(select 1 from public.agents a where a.profile_id=profiles.id and public.can_manage_supervised_agent(a.id)));
create policy supervisor_documents_read on public.agent_documents for select to authenticated
using(public.is_scoped_supervisor() and public.can_manage_supervised_agent(agent_id));
create policy supervisor_document_files on storage.objects for select to authenticated
using(bucket_id='agent-documents' and public.is_scoped_supervisor() and exists(
select 1 from public.agent_documents d where d.storage_path=storage.objects.name and public.can_manage_supervised_agent(d.agent_id)));
create policy supervisor_exclusive_document_files on storage.objects as restrictive for select to authenticated
using(not public.is_scoped_supervisor() or bucket_id<>'agent-documents' or exists(
select 1 from public.agent_documents d where d.storage_path=storage.objects.name and public.can_manage_supervised_agent(d.agent_id)));
create policy supervisor_categories_manage on public.agent_service_categories for all to authenticated
using(public.is_scoped_supervisor() and public.can_manage_supervised_agent(agent_id))
with check(public.is_scoped_supervisor() and public.can_manage_supervised_agent(agent_id));

-- Only service-created accounts can carry this protected app_metadata claim.
-- Public signup user_metadata cannot claim or steal team ownership.
create function public.guard_agent_supervisor_assignment() returns trigger
language plpgsql security definer set search_path=public as $$
declare creator uuid; begin
 if tg_op='INSERT' and new.supervisor_id is null then
   select nullif(raw_app_meta_data->>'created_by_supervisor','')::uuid into creator from auth.users where id=new.profile_id;
   if creator is not null then new.supervisor_id:=creator; end if;
 end if;
 if tg_op='UPDATE' and new.supervisor_id is distinct from old.supervisor_id
    and not public.is_super_admin() then
   raise exception 'Only Super Admin can transfer agent supervision' using errcode='42501';
 end if;
 if tg_op='INSERT' and new.supervisor_id is not null and creator is null and not public.is_super_admin() then
   raise exception 'Only Super Admin can assign an agent team' using errcode='42501';
 end if;
 if new.supervisor_id is not null and not (
   public.is_scoped_supervisor(new.supervisor_id)
   and public.has_admin_permission('agents.manage',new.supervisor_id)
   and public.supervisor_location_contains(new.supervisor_id,new.location_id)
 ) then raise exception 'Agent location must be inside the active supervisor territory' using errcode='23514'; end if;
 return new;
end $$;
create trigger guard_agent_supervisor_assignment before insert or update of supervisor_id,location_id
on public.agents for each row execute function public.guard_agent_supervisor_assignment();

create function public.guard_supervisor_location_tree() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if exists(select 1 from public.agents a join public.supervisor_territories t on t.supervisor_id=a.supervisor_id
 where t.is_active and not public.supervisor_location_contains(a.supervisor_id,a.location_id)) then
   raise exception 'Transfer agents or deactivate the supervisor territory before moving or disabling this location';
 end if;
 return new;
end $$;
create trigger guard_supervisor_location_tree after update of parent_id,is_active on public.locations
for each row when(old.parent_id is distinct from new.parent_id or old.is_active is distinct from new.is_active)
execute function public.guard_supervisor_location_tree();

create function public.get_my_supervisor_context() returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('scoped',public.is_scoped_supervisor(),
 'supervisor_id',case when public.is_scoped_supervisor() then auth.uid() end,
 'location_id',t.location_id,'location_name',l.name,'location_type',l.location_type,
 'active',coalesce(t.is_active and public.has_admin_permission('agents.manage'),false))
 from (select 1) seed left join public.supervisor_territories t on t.supervisor_id=auth.uid()
 left join public.locations l on l.id=t.location_id
$$;
create function public.get_agent_creation_scope(p_location_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
begin
 if not public.has_admin_permission('agents.manage') then raise exception 'Agent management access required' using errcode='42501'; end if;
 if not public.is_valid_agent_location(p_location_id) then raise exception 'Choose an active area for the agent'; end if;
 if public.is_scoped_supervisor() and not public.supervisor_location_contains(auth.uid(),p_location_id) then
   raise exception 'Choose a location inside your assigned territory' using errcode='42501'; end if;
 return public.get_my_supervisor_context();
end $$;

create function public.configure_supervisor_territory(p_email text,p_location_id uuid,p_active boolean default true)
returns void language plpgsql security definer set search_path=public as $$
declare target uuid; begin
 if not public.is_super_admin() then raise exception 'Only Super Admin can assign supervisor territories' using errcode='42501'; end if;
 lock table public.agents in share row exclusive mode;
 select id into target from public.profiles where lower(account_email)=lower(btrim(p_email));
 if target is null then raise exception 'Registered account not found'; end if;
 if public.is_super_admin(target) then raise exception 'Super Admin keeps global access and cannot be a scoped supervisor'; end if;
 if not exists(select 1 from public.locations where id=p_location_id and is_active and location_type::text<>'country') then
   raise exception 'Choose an active region, district, ward or local area'; end if;
 perform pg_advisory_xact_lock(hashtextextended(target::text,0));
 perform public.assign_admin_role(target,'supervisor',true);
 insert into public.supervisor_territories(supervisor_id,location_id,is_active,assigned_by)
 values(target,p_location_id,p_active,auth.uid()) on conflict(supervisor_id) do update
 set location_id=excluded.location_id,is_active=excluded.is_active,assigned_by=excluded.assigned_by,updated_at=now();
 if p_active and exists(select 1 from public.agents where supervisor_id=target and not public.supervisor_location_contains(target,location_id)) then
   raise exception 'Transfer agents outside the new territory before changing this location'; end if;
 insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
 values(auth.uid(),'supervisor_territory_configured','supervisor_territories',target,jsonb_build_object('location_id',p_location_id,'active',p_active));
end $$;

create function public.assign_agent_supervisor(p_agent_id uuid,p_supervisor_id uuid default null)
returns void language plpgsql security definer set search_path=public as $$
declare previous uuid; begin
 if not public.is_super_admin() then raise exception 'Only Super Admin can assign or transfer agents' using errcode='42501'; end if;
 select supervisor_id into previous from public.agents where id=p_agent_id for update;
 if not found then raise exception 'Agent not found'; end if;
 update public.agents set supervisor_id=p_supervisor_id where id=p_agent_id;
 insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
 values(auth.uid(),'agent_supervisor_assigned','agents',p_agent_id,jsonb_build_object('previous_supervisor_id',previous,'supervisor_id',p_supervisor_id));
end $$;

create function public.get_supervisor_directory() returns jsonb
language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_super_admin() then raise exception 'Only Super Admin can view all supervisors' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('supervisor_id',a.user_id,'full_name',p.full_name,
 'account_email',p.account_email,'location_id',t.location_id,'location_name',l.name,'is_active',coalesce(t.is_active,false),
 'agent_count',(select count(*) from public.agents ag where ag.supervisor_id=a.user_id)) order by p.full_name)
 from public.admin_role_assignments a join public.profiles p on p.id=a.user_id
 left join public.supervisor_territories t on t.supervisor_id=a.user_id left join public.locations l on l.id=t.location_id
 where a.role_id='supervisor'),'[]'::jsonb);
end $$;

-- Clear stale blanket-role claims from the role definition; the scoped marker is UI-only.
update public.admin_role_definitions set permissions='["agents.manage","supervisor.scoped"]'::jsonb,
description='Manage only assigned agents within an assigned location. Only Super Admin can transfer agents.' where id='supervisor';
revoke all on function public.is_scoped_supervisor(uuid),public.supervisor_location_contains(uuid,uuid),
 public.can_manage_supervised_agent(uuid,uuid),public.get_my_supervisor_context(),public.get_agent_creation_scope(uuid),
 public.configure_supervisor_territory(text,uuid,boolean),public.assign_agent_supervisor(uuid,uuid),public.get_supervisor_directory()
 from public,anon;
grant execute on function public.is_scoped_supervisor(uuid),public.supervisor_location_contains(uuid,uuid),
 public.can_manage_supervised_agent(uuid,uuid),public.get_my_supervisor_context(),public.get_agent_creation_scope(uuid),
 public.configure_supervisor_territory(text,uuid,boolean),public.assign_agent_supervisor(uuid,uuid),public.get_supervisor_directory()
 to authenticated,service_role;
notify pgrst,'reload schema';
