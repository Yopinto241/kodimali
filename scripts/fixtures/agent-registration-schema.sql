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
\ir supervisor-existing-guards.sql
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
\ir ../../supabase/migrations/20261031100000_agent_supervisor_role.sql
\ir ../../supabase/migrations/20261031110000_supervisor_territories_and_exclusive_agents.sql
\ir ../../supabase/migrations/20260628162000_search_admin_agents.sql

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
