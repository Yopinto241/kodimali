\set ON_ERROR_STOP on
\ir fixtures/agent-registration-schema.sql
\ir fixtures/agent-registration-functions.sql
alter table locations alter column id set default gen_random_uuid();
create or replace function public.normalize_location_name(raw_name text) returns text language sql immutable as $$ select nullif(regexp_replace(btrim(coalesce(raw_name,'')), '\s+', ' ', 'g'),''); $$;
\ir ../supabase/migrations/20260627110000_fix_ensure_ward_area_ambiguity.sql
insert into locations(id,parent_id,name,location_type) values(pg_temp.f(110),pg_temp.f(104),'Empty Ward','ward');
set local role anon;
select pg_temp.check_true((select created_new from ensure_ward_area(pg_temp.f(110),'  Mtaa   Mpya  ')),'public applicant can save a typed area before signup');
select pg_temp.check_true(not (select created_new from ensure_ward_area(pg_temp.f(110),'mtaa mpya')),'next applicant reuses the same area regardless of case');
reset role;
select pg_temp.check_true((select count(*)=1 from locations where parent_id=pg_temp.f(110) and lower(name)='mtaa mpya'),'one normalized shared area');
select pg_temp.check_true((select public.is_valid_agent_location(id) from locations where parent_id=pg_temp.f(110)),'saved area passes registration hierarchy validation');
do $$ begin
 perform ensure_ward_area(pg_temp.f(104),'Wrong parent');
 raise exception 'FAIL: area saved outside a ward';
exception when raise_exception then if sqlerrm not like 'Ward was not found%' then raise; end if; end $$;
select 'PASS anonymous typed-area save, normalized reuse, registration validity and parent enforcement';
rollback;
