\set ON_ERROR_STOP on
begin;
create schema if not exists auth;
do $$ begin if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if; end $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create type public.app_role as enum('customer','admin','agent');
create type public.location_type as enum('country','region','district','ward','area','street');
create table profiles(id uuid primary key,full_name text,account_email text,phone_number text,preferred_language text,account_email_confirmed_at timestamptz,created_at timestamptz,updated_at timestamptz);
create table user_roles(profile_id uuid,role public.app_role);
create function public.is_admin(uuid default auth.uid()) returns boolean language sql stable as $$ select exists(select 1 from user_roles where profile_id=$1 and role='admin') $$;
create function public.has_admin_permission(text) returns boolean language sql stable as $$ select public.is_admin() and ($1=any(string_to_array(current_setting('test.permissions',true),',')) or current_setting('test.permissions',true)='*') $$;
create table locations(id uuid primary key default gen_random_uuid(),parent_id uuid references locations(id) on delete cascade,name text not null,location_type public.location_type not null,is_active boolean default true);
create unique index locations_name_unique on locations(coalesce(parent_id,'00000000-0000-0000-0000-000000000000'::uuid),location_type,lower(name));
\ir fixtures/manage-location-hierarchy.sql
alter table locations enable row level security;
create policy locations_active_public on locations for select using(is_active);
create policy locations_admin_all on locations for all using(public.is_admin()) with check(public.is_admin());
grant select,insert,update,delete on locations to authenticated;
create table location_hidden_references(id uuid primary key default gen_random_uuid(),location_id uuid references locations(id) on delete set null);
alter table location_hidden_references enable row level security;
grant usage on schema public,auth to authenticated;
grant select on user_roles to authenticated;
\ir ../supabase/migrations/20261030150000_manage_directory_and_safe_locations.sql

create function pg_temp.check_true(value boolean,label text) returns void language plpgsql as $$ begin if value is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
insert into profiles
select ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'Customer '||n,'customer'||n||'@example.invalid','255700000000','sw',case when n%2=0 then now() end,'2026-01-01'::timestamptz+n*interval '1 minute',now() from generate_series(1,55)n;
insert into user_roles select id,'customer' from profiles;
insert into user_roles values ('00000000-0000-4000-8000-000000000001','admin'),('00000000-0000-4000-8000-000000000002','agent');
select set_config('test.uid','00000000-0000-4000-8000-000000000001',true),set_config('test.permissions','users.view,agents.manage',true);
set local role authenticated;
select pg_temp.check_true((select count(*)=20 from search_manage_customers()),'bounded first page');
select pg_temp.check_true((select count(*)=13 from search_manage_customers(p_offset=>40)),'last page');
select pg_temp.check_true((select count(*)=1 from search_manage_customers(p_search=>'customer55@example.invalid')),'search beyond first page');
select pg_temp.check_true((select count(*)=0 from search_manage_customers(p_search=>'Customer 1',p_id=>'00000000-0000-4000-8000-000000000001')),'staff excluded');
select pg_temp.check_true((select bool_and(email_confirmed_at is null) from search_manage_customers(p_confirmation=>'pending')),'confirmation filter');
select pg_temp.check_true((select count(*)=0 from search_manage_customers(p_search=>'%')),'search is literal');
select set_config('test.permissions','payments.manage',true);
do $$ begin perform search_manage_customers(); raise exception 'FAIL: directory permission bypass'; exception when insufficient_privilege then null; end $$;
select set_config('test.uid','00000000-0000-4000-8000-000000000003',true),set_config('test.permissions','*',true);
do $$ begin perform search_manage_customers(); raise exception 'FAIL: customer directory access'; exception when insufficient_privilege then null; end $$;
do $$ begin insert into locations(name,location_type) values('Unauthorized','country'); raise exception 'FAIL: direct location write'; exception when insufficient_privilege then null; end $$;
do $$ begin perform manage_delete_unused_location(gen_random_uuid()); raise exception 'FAIL: customer location access'; exception when insufficient_privilege then null; end $$;
reset role;
select set_config('test.uid','00000000-0000-4000-8000-000000000001',true),set_config('test.permissions','agents.manage',true);
insert into locations(id,name,location_type) values('10000000-0000-4000-8000-000000000001','Tanzania','country');
insert into locations(id,parent_id,name,location_type) values('10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','Arusha','region');
insert into locations(id,parent_id,name,location_type) values
('10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000002','Arusha District','district'),
('10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000003','Sokoni','ward'),
('10000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000004','Central','area');
select pg_temp.check_true((select count(*)=1 from locations where parent_id='10000000-0000-4000-8000-000000000002' and location_type='district'),'region children');
select pg_temp.check_true((select count(*)=1 from locations where parent_id='10000000-0000-4000-8000-000000000003' and location_type='ward'),'district children');
select pg_temp.check_true((select count(*)=1 from locations where parent_id='10000000-0000-4000-8000-000000000004' and location_type='area'),'ward children');
do $$ begin insert into locations(parent_id,name,location_type) values('10000000-0000-4000-8000-000000000004',' central ','area'); raise exception 'FAIL: duplicate'; exception when unique_violation then null; end $$;
do $$ begin insert into locations(parent_id,name,location_type) values('10000000-0000-4000-8000-000000000002','Invalid ward','ward'); exception when raise_exception then if sqlerrm not like 'Ward must belong%' then raise; end if; end $$;
update locations set name='Renamed ward' where id='10000000-0000-4000-8000-000000000004';
select pg_temp.check_true((select parent_id='10000000-0000-4000-8000-000000000004' from locations where location_type='area'),'rename preserves relationships');
select manage_delete_unused_location('10000000-0000-4000-8000-000000000005');
select manage_delete_unused_location('10000000-0000-4000-8000-000000000004');
select manage_delete_unused_location('10000000-0000-4000-8000-000000000003');
do $$ begin perform manage_delete_unused_location('10000000-0000-4000-8000-000000000001'); raise exception 'FAIL: cascade deletion'; exception when foreign_key_violation then null; end $$;
insert into location_hidden_references(location_id) values('10000000-0000-4000-8000-000000000002');
set local role authenticated;
do $$ begin perform manage_delete_unused_location('10000000-0000-4000-8000-000000000002'); raise exception 'FAIL: hidden reference cleared'; exception when foreign_key_violation then null; end $$;
reset role;
select pg_temp.check_true((select location_id is not null from location_hidden_references limit 1),'hidden reference preserved');
delete from location_hidden_references;
set local role authenticated;
select manage_delete_unused_location('10000000-0000-4000-8000-000000000002');
reset role;
select pg_temp.check_true(not exists(select 1 from locations where name='Arusha'),'unused location deleted');
select pg_temp.check_true(exists(select 1 from locations where name='Tanzania'),'parent preserved');
rollback;
\echo PASS customer search, pagination, permissions, cascade and hidden-reference protection
