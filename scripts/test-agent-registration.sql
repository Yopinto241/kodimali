\set ON_ERROR_STOP on
\ir fixtures/agent-registration-schema.sql
alter table profiles add column updated_at timestamptz default now();
alter table auth.users add column email text,add column email_confirmed_at timestamptz;
alter table agents add unique(profile_id);
\ir fixtures/agent-registration-functions.sql
create trigger guard_agent_location_hierarchy before insert or update of location_id on agents for each row execute function guard_agent_location_hierarchy();
create trigger signup_agent after insert on auth.users for each row execute function handle_auth_user_created();
create function pg_temp.customer_role() returns trigger language plpgsql as $$ begin insert into public.user_roles values(new.id,'customer') on conflict do nothing; return new; end $$;
create trigger fixture_customer after insert on profiles for each row execute function pg_temp.customer_role();
insert into asset_categories(id,name,slug) values(pg_temp.f(301),'Property','house');
do $$ begin
 insert into auth.users(id,email,raw_user_meta_data) values(pg_temp.f(500),'fixture@example.invalid',jsonb_build_object('username','fixture_agent','full_name','Fixture Agent','register_as_agent',true,'location_id',pg_temp.f(104),'primary_category_id',pg_temp.f(301)));
 raise exception 'FAIL: district accepted by agent signup';
exception when raise_exception then
 if sqlerrm not like 'Agent location must be an active area%' then raise; end if;
end $$;
select pg_temp.check_true(not exists(select 1 from auth.users where id=pg_temp.f(500)) and not exists(select 1 from profiles where id=pg_temp.f(500)),'invalid district rolls back account and profile');
insert into auth.users(id,email,raw_user_meta_data) values(pg_temp.f(500),'fixture@example.invalid',jsonb_build_object('username','fixture_agent','full_name','Fixture Agent','register_as_agent',true,'location_id',pg_temp.f(108),'primary_category_id',pg_temp.f(301)));
select pg_temp.check_true(exists(select 1 from agents where profile_id=pg_temp.f(500) and location_id=pg_temp.f(108) and verification_status='pending' and account_status='inactive'),'valid area creates pending inactive agent');
select pg_temp.check_true((select count(*)=2 from user_roles where profile_id=pg_temp.f(500) and role in ('agent','customer')),'normal customer role retained');
select pg_temp.check_true(exists(select 1 from agent_service_categories c join agents a on a.id=c.agent_id where a.profile_id=pg_temp.f(500) and c.category_id=pg_temp.f(301) and c.is_primary),'primary service category saved');
select 'PASS district rejection reproduced, transactional rollback, valid area signup and approval gate';
rollback;
