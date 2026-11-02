\set ON_ERROR_STOP on
begin;
create schema auth;
create schema storage;
do $$ begin
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
end $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create function pg_temp.f(n int) returns uuid language sql immutable as $$ select ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.check_true(value boolean,label text) returns void language plpgsql as $$ begin if value is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create type public.app_role as enum('admin','customer','agent','owner');
create type public.location_type as enum('country','region','district','ward','area','street');
create type public.agent_account_status as enum('inactive','active','deactivated','suspended');
create type public.agent_verification_status as enum('pending','approved','rejected');
create table auth.users(id uuid primary key,raw_app_meta_data jsonb default '{}',raw_user_meta_data jsonb default '{}');
create table profiles(id uuid primary key,full_name text,username text,account_email text,account_email_confirmed_at timestamptz,preferred_language text,phone_number text,avatar_url text);
create table user_roles(profile_id uuid,role public.app_role,primary key(profile_id,role));
create table admin_role_definitions(id text primary key,name text,description text,permissions jsonb,rank int,is_active boolean default true);
create table admin_role_assignments(user_id uuid,role_id text references admin_role_definitions(id),assigned_by uuid,assigned_at timestamptz default now(),primary key(user_id,role_id));
create table locations(id uuid primary key,parent_id uuid references locations(id),name text,location_type public.location_type,is_active boolean default true);
create table agents(id uuid primary key default gen_random_uuid(),profile_id uuid references profiles(id),display_name text,phone_number text,contact_email text,nida_number text,location_id uuid references locations(id),public_location_label text,profile_photo_path text,verified_at timestamptz,business_name text,business_description text,verification_status public.agent_verification_status default 'pending',account_status public.agent_account_status default 'inactive',activated_at timestamptz,deactivated_at timestamptz,deactivation_reason text,admin_notes text,average_response_minutes numeric,created_at timestamptz default now());
create table agent_documents(id uuid primary key default gen_random_uuid(),agent_id uuid references agents(id),document_type text,storage_path text);
create table asset_categories(id uuid primary key,name text,slug text,icon_key text);
create table agent_service_categories(agent_id uuid references agents(id),category_id uuid references asset_categories(id),is_primary boolean,primary key(agent_id,category_id));
create table audit_logs(id uuid default gen_random_uuid(),actor_id uuid,action text,target_table text,target_id uuid,metadata jsonb);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
create function public.is_super_admin(check_user uuid default auth.uid()) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from admin_role_assignments where user_id=check_user and role_id='super_admin') $$;
create function public.is_admin(check_user uuid default auth.uid()) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from user_roles where profile_id=check_user and role='admin') $$;
create function public.has_admin_permission(p_permission text,check_user uuid default auth.uid()) returns boolean language sql stable as $$ select public.is_admin(check_user) $$;
create function public.is_valid_agent_location(check_location_id uuid) returns boolean language sql stable as $$ select exists(select 1 from locations where id=check_location_id and location_type='area' and is_active) $$;
\ir fixtures/supervisor-existing-guards.sql
create trigger guard_agent_account_update before insert or update on agents for each row execute function public.guard_agent_account_update();
create trigger protect_agent_verification_fields before update on agents for each row execute function public.protect_agent_verification_fields();
alter table agents enable row level security;
alter table profiles enable row level security;
alter table user_roles enable row level security;
alter table agent_documents enable row level security;
alter table agent_service_categories enable row level security;
alter table storage.objects enable row level security;
create policy agents_admin_only on agents for all using(public.is_admin()) with check(public.is_admin());
create policy profiles_self_or_admin_select on profiles for select using(id=auth.uid() or public.is_admin());
create policy user_roles_admin_only on user_roles for all using(public.is_admin()) with check(public.is_admin());
create policy user_roles_self on user_roles for select using(profile_id=auth.uid());
create policy agent_documents_admin on agent_documents for all using(public.is_admin()) with check(public.is_admin());
create policy agent_service_categories_admin_all on agent_service_categories for all using(public.is_admin()) with check(public.is_admin());
create policy storage_admin on storage.objects for all using(public.is_admin()) with check(public.is_admin());
grant usage on schema public,auth,storage to authenticated;
grant select,insert,update,delete on all tables in schema public,storage to authenticated;
\ir ../supabase/migrations/20261031100000_agent_supervisor_role.sql
\ir ../supabase/migrations/20261031110000_supervisor_territories_and_exclusive_agents.sql
\ir ../supabase/migrations/20260628162000_search_admin_agents.sql

insert into profiles select pg_temp.f(n),'Person '||n,'person'||n,'person'||n||'@example.invalid',now(),'sw','255700000000',null from generate_series(1,12)n;
insert into auth.users(id) select id from profiles;
insert into admin_role_definitions(id,name,permissions,rank) values('super_admin','Super Admin','["*"]',100),('agent_manager','Agent Manager','["agents.manage"]',70),('finance_admin','Finance','["payments.manage"]',70);
insert into admin_role_assignments(user_id,role_id) values(pg_temp.f(1),'super_admin'),(pg_temp.f(5),'agent_manager');
insert into user_roles values(pg_temp.f(1),'admin'),(pg_temp.f(5),'admin');
insert into locations(id,parent_id,name,location_type) values
 (pg_temp.f(101),null,'Tanzania','country'),
 (pg_temp.f(102),pg_temp.f(101),'Region A','region'),(pg_temp.f(103),pg_temp.f(101),'Region B','region'),
 (pg_temp.f(104),pg_temp.f(102),'District A','district'),(pg_temp.f(105),pg_temp.f(103),'District B','district'),
 (pg_temp.f(106),pg_temp.f(104),'Ward A','ward'),(pg_temp.f(107),pg_temp.f(105),'Ward B','ward'),
 (pg_temp.f(108),pg_temp.f(106),'Area A','area'),(pg_temp.f(109),pg_temp.f(107),'Area B','area');
select set_config('test.uid',pg_temp.f(1)::text,true);
select configure_supervisor_territory('person2@example.invalid',pg_temp.f(102));
select configure_supervisor_territory('person3@example.invalid',pg_temp.f(102));
select configure_supervisor_territory('person4@example.invalid',pg_temp.f(103));
insert into agents(id,profile_id,location_id) values(pg_temp.f(201),pg_temp.f(6),pg_temp.f(108)),(pg_temp.f(202),pg_temp.f(7),pg_temp.f(108)),(pg_temp.f(203),pg_temp.f(8),pg_temp.f(109));
select assign_agent_supervisor(pg_temp.f(201),pg_temp.f(2));
select assign_agent_supervisor(pg_temp.f(202),pg_temp.f(3));
select assign_agent_supervisor(pg_temp.f(203),pg_temp.f(4));
do $$ begin update locations set parent_id=pg_temp.f(105) where id=pg_temp.f(106); raise exception 'FAIL: hierarchy move escapes territory'; exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end $$;
insert into agent_documents(agent_id,document_type,storage_path) values(pg_temp.f(201),'id','agent-a/id.pdf'),(pg_temp.f(202),'id','agent-b/id.pdf');
insert into storage.objects(bucket_id,name) values('agent-documents','agent-a/id.pdf'),('agent-documents','agent-b/id.pdf');
insert into asset_categories values(pg_temp.f(301),'Apartment','apartment','home');
insert into agent_service_categories values(pg_temp.f(201),pg_temp.f(301),true),(pg_temp.f(202),pg_temp.f(301),true);

select set_config('test.uid',pg_temp.f(2)::text,true);
set local role authenticated;
select pg_temp.check_true(not public.is_admin(),'supervisor not blanket administrator');
select pg_temp.check_true(not has_function_privilege('anon','public.assign_agent_supervisor(uuid,uuid)','execute'),'anonymous cannot assign agents');
select pg_temp.check_true(not has_function_privilege('anon','public.configure_supervisor_territory(text,uuid,boolean)','execute'),'anonymous cannot configure territories');
select pg_temp.check_true(public.has_admin_permission('agents.manage') and not public.has_admin_permission('payments.manage'),'scoped permissions');
select pg_temp.check_true((select count(*)=1 from agents),'one own agent only despite overlapping territory');
select pg_temp.check_true((select count(*)=1 from search_admin_agents()),'search cannot return another supervisor team');
select pg_temp.check_true((select count(*)=1 from agent_documents),'private documents isolated');
select pg_temp.check_true((select count(*)=1 from storage.objects),'private document files isolated');
select pg_temp.check_true((select count(*)=2 from profiles),'only own profile and assigned agent profile');
select pg_temp.check_true((select count(*)=1 from agent_service_categories),'category assignments isolated');
select pg_temp.check_true(public.can_manage_supervised_agent(pg_temp.f(201)) and not public.can_manage_supervised_agent(pg_temp.f(202)),'overlapping supervisor cannot manage peer team');
select get_agent_creation_scope(pg_temp.f(108));
do $$ begin perform get_agent_creation_scope(pg_temp.f(109)); raise exception 'FAIL: out of territory creation'; exception when insufficient_privilege then null; end $$;
do $$ begin perform assign_agent_supervisor(pg_temp.f(202),pg_temp.f(2)); raise exception 'FAIL: supervisor steals agent'; exception when insufficient_privilege then null; end $$;
do $$ begin perform configure_supervisor_territory('person2@example.invalid',pg_temp.f(103)); raise exception 'FAIL: supervisor changes own territory'; exception when insufficient_privilege then null; end $$;
update agents set supervisor_id=pg_temp.f(2) where id=pg_temp.f(202);
select pg_temp.check_true((select count(*)=1 from agents),'direct update cannot steal invisible team');
do $$ begin insert into user_roles values(pg_temp.f(2),'owner'); raise exception 'FAIL: supervisor role escalation'; exception when insufficient_privilege then null; end $$;
do $$ begin insert into agent_service_categories values(pg_temp.f(203),pg_temp.f(301),true); raise exception 'FAIL: foreign category mutation'; exception when insufficient_privilege then null; end $$;
reset role;

-- A service-created account is automatically assigned, before any agent is visible.
update auth.users set raw_app_meta_data=jsonb_build_object('created_by_supervisor',pg_temp.f(2)) where id=pg_temp.f(9);
select set_config('request.jwt.claim.role','service_role',true);
insert into agents(id,profile_id,location_id) values(pg_temp.f(204),pg_temp.f(9),pg_temp.f(108));
select pg_temp.check_true((select supervisor_id=pg_temp.f(2) from agents where id=pg_temp.f(204)),'created agent automatically belongs to creator');
update auth.users set raw_app_meta_data=jsonb_build_object('created_by_supervisor',pg_temp.f(2)) where id=pg_temp.f(10);
do $$ begin insert into agents(id,profile_id,location_id) values(pg_temp.f(205),pg_temp.f(10),pg_temp.f(109)); raise exception 'FAIL: service-created agent outside territory'; exception when check_violation then null; end $$;
update auth.users set raw_user_meta_data=jsonb_build_object('created_by_supervisor',pg_temp.f(2)) where id=pg_temp.f(11);
insert into agents(id,profile_id,location_id) values(pg_temp.f(206),pg_temp.f(11),pg_temp.f(108));
select pg_temp.check_true((select supervisor_id is null from agents where id=pg_temp.f(206)),'public user metadata cannot claim a team');
select set_config('request.jwt.claim.role','',true),set_config('test.uid',pg_temp.f(1)::text,true);

-- Transfers are exclusive and revoke old ownership immediately.
select assign_agent_supervisor(pg_temp.f(201),pg_temp.f(3));
select set_config('test.uid',pg_temp.f(2)::text,true);
set local role authenticated;
select pg_temp.check_true(not public.can_manage_supervised_agent(pg_temp.f(201)),'old supervisor immediately loses agent');
select pg_temp.check_true((select count(*)=1 from agents),'old supervisor sees only remaining own agent');
reset role;
select set_config('test.uid',pg_temp.f(1)::text,true);
do $$ begin perform assign_agent_supervisor(pg_temp.f(201),pg_temp.f(4)); raise exception 'FAIL: transfer outside destination territory'; exception when check_violation then null; end $$;
do $$ begin perform configure_supervisor_territory('person3@example.invalid',pg_temp.f(103)); raise exception 'FAIL: move territory around existing agents'; exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if; end $$;
select configure_supervisor_territory('person2@example.invalid',pg_temp.f(102),false);
select set_config('test.uid',pg_temp.f(2)::text,true);
set local role authenticated;
select pg_temp.check_true((select count(*)=0 from agents),'inactive territory has no team access');
reset role;
select set_config('test.uid',pg_temp.f(1)::text,true);
select assign_admin_role(pg_temp.f(2),'supervisor',false);
select set_config('test.uid',pg_temp.f(2)::text,true);
select pg_temp.check_true(not public.is_admin() and not public.has_admin_permission('agents.manage'),'role removal cannot become unrestricted admin');
select set_config('test.uid',pg_temp.f(1)::text,true);
set local role authenticated;
select pg_temp.check_true((select count(*)=5 from agents),'Super Admin retains all agents');
reset role;
select set_config('test.uid',pg_temp.f(5)::text,true);
set local role authenticated;
select pg_temp.check_true((select count(*)=5 from agents),'existing Agent Manager remains functional');
do $$ begin update agents set supervisor_id=pg_temp.f(5) where id=pg_temp.f(201); raise exception 'FAIL: Agent Manager changes team ownership'; exception when insufficient_privilege then null; end $$;
reset role;
select 'PASS supervisor isolation, geography, creation, transfers, revocation and legacy staff';

\ir ../supabase/migrations/20261101010000_supervisor_agent_first.sql
select set_config('test.uid',pg_temp.f(1)::text,true);
do $$ begin
 perform configure_supervisor_territory('person12@example.invalid',pg_temp.f(102));
 raise exception 'FAIL: customer promoted without agent registration';
exception when check_violation then null; end $$;
do $$ begin
 perform assign_admin_role(pg_temp.f(12),'supervisor',true);
 raise exception 'FAIL: generic role editor bypassed agent registration';
exception when check_violation then null; end $$;
update auth.users set raw_app_meta_data='{}' where id=pg_temp.f(10);
insert into agents(profile_id,location_id) values(pg_temp.f(10),pg_temp.f(108)),(pg_temp.f(11),pg_temp.f(108));
update agents set supervisor_id=pg_temp.f(3) where profile_id=pg_temp.f(11);
do $$ begin
 perform configure_supervisor_territory('person11@example.invalid',pg_temp.f(102));
 raise exception 'FAIL: subordinate agent promoted without release';
exception when check_violation then null; end $$;
select set_config('test.uid',pg_temp.f(5)::text,true);
do $$ begin
 perform configure_supervisor_territory('person10@example.invalid',pg_temp.f(102));
 raise exception 'FAIL: Agent Manager appointed supervisor';
exception when insufficient_privilege then null; end $$;
select set_config('test.uid',pg_temp.f(1)::text,true);
select configure_supervisor_territory('person10@example.invalid',pg_temp.f(102));
select pg_temp.check_true(exists(select 1 from admin_role_assignments where user_id=pg_temp.f(10) and role_id='supervisor'),'registered agent promoted by Super Admin');
select configure_supervisor_territory('person10@example.invalid',pg_temp.f(102),false);
select configure_supervisor_territory('person10@example.invalid',pg_temp.f(102),true);
select pg_temp.check_true(public.has_admin_permission('agents.manage',pg_temp.f(10)),'promoted agent has active scoped management');
select pg_temp.check_true(not public.has_admin_permission('payments.manage',pg_temp.f(10)),'promotion does not grant finance');
select 'PASS agent-first promotion, direct role bypass, exclusive team release, Super Admin only and reactivation';

\ir ../supabase/migrations/20261101160000_supervisor_own_agent_workspace.sql
select set_config('test.uid',pg_temp.f(10)::text,true);
set local role authenticated;
select pg_temp.check_true((select count(*)=1 from agents where profile_id=auth.uid()),'Supervisor can read own agent record in agent workspace');
select pg_temp.check_true((select count(*)=0 from agents where profile_id=pg_temp.f(7)),'Supervisor cannot read another supervisors agent');
select pg_temp.check_true(not public.can_manage_supervised_agent((select id from agents where profile_id=auth.uid())),'Own read does not grant team management of oneself');
with changed as (update agents set business_name='Not allowed' where profile_id=auth.uid() returning id)
select pg_temp.check_true((select count(*)=0 from changed),'Supervisor cannot use own read exception for profile writes');
with removed as (delete from agents where profile_id=auth.uid() returning id)
select pg_temp.check_true((select count(*)=0 from removed),'Supervisor cannot delete own agent record');
reset role;
select 'PASS supervisor own workspace read, exclusive teams and unchanged write restrictions';
rollback;
