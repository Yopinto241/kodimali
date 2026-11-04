"""Reproduce deployed-policy defects in a disposable localhost database only.

These probes assert the observed defect, not desired secure behavior.
They do not read customer rows or modify the linked database.
"""
import json, os, subprocess, uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
catalog=json.loads((ROOT/'tmp/platform-audit/live-catalog.json').read_text(encoding='utf-8'))
functions={f['name']:f for f in catalog['functions']}
env={**os.environ,'PGHOST':'127.0.0.1','PGPORT':'55439','PGUSER':'postgres','PGPASSWORD':'','PGCLIENTENCODING':'UTF8'}
db='audit_policy_'+uuid.uuid4().hex[:10]
def run(sql,database=db):
 return subprocess.run(['D:/PostgreSQL/18/bin/psql.exe','-X','-w','-v','ON_ERROR_STOP=1','-d',database,'-f','-'],input=sql,cwd=ROOT,env=env,capture_output=True,text=True,encoding='utf-8',timeout=60)
r=run('create database '+db,'postgres');assert r.returncode==0,r.stderr
sql="""
begin;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create table public.user_roles(profile_id uuid,role text);
create table public.admin_role_assignments(user_id uuid,role_id text);
create table public.admin_role_definitions(id text,is_active boolean,permissions jsonb);
create table public.supervisor_territories(supervisor_id uuid,is_active boolean);
"""
for name in ['is_super_admin','is_scoped_supervisor','is_admin','has_admin_permission']:
 sql+=functions[name]['definition']+';\n'
sql+="""
create table public.booking_requests(id uuid,customer_id uuid,agent_id uuid,customer_phone text);
create function public.is_agent_active() returns boolean language sql as $$ select false $$;
create function public.current_agent_id_for_user() returns uuid language sql as $$ select null::uuid $$;
alter table public.booking_requests enable row level security;
grant usage on schema public,auth to authenticated;
grant select on public.booking_requests to authenticated;
insert into public.user_roles values('00000000-0000-4000-8000-000000000001','admin');
insert into public.admin_role_assignments values('00000000-0000-4000-8000-000000000001','analyst');
insert into public.admin_role_definitions values('analyst',true,'["analytics.view"]');
insert into public.booking_requests values('00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003',null,'FIXTURE PRIVATE PHONE');
"""
policy=next(p for p in catalog['policies'] if p['policyname']=='bookings_active_agent_or_admin_select')
assert policy['permissive']=='PERMISSIVE'
sql+='create policy observed_legacy_booking_select on public.booking_requests for select to authenticated using ('+policy['qual']+');\n'
sql+="""
select set_config('test.uid','00000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $$ begin
 if public.has_admin_permission('bookings.manage') then raise exception 'Fixture unexpectedly has booking permission'; end if;
 if (select count(*) from public.booking_requests where customer_phone='FIXTURE PRIVATE PHONE')<>1 then raise exception 'Expected legacy policy bypass was not reproduced'; end if;
 raise notice 'REPRODUCED: analyst without bookings.manage can read unrelated private booking data through deployed legacy policy';
end $$;
reset role;
create table public.listing_chat_payments(id uuid,listing_id uuid,agent_id uuid,customer_id uuid,payment_status text);
create table public.listing_chat_access(listing_id uuid,agent_id uuid,customer_id uuid,payment_id uuid,access_source text,starts_at timestamptz,expires_at timestamptz,revoked_at timestamptz,updated_at timestamptz,unique(customer_id,listing_id,agent_id));
insert into public.listing_chat_payments values('00000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000007','paid');
"""
assert functions['grant_listing_chat_access']['anon_execute'] is True
sql+=functions['grant_listing_chat_access']['definition']+';\n'
sql+="""
grant usage on schema public to anon;
set local role anon;
select public.grant_listing_chat_access('00000000-0000-4000-8000-000000000004');
select public.grant_listing_chat_access('00000000-0000-4000-8000-000000000004');
reset role;
do $$ begin
 if not exists(select from public.listing_chat_access where expires_at>=now()+interval '13 days') then raise exception 'Expected duplicate entitlement extension not reproduced'; end if;
 raise notice 'REPRODUCED: anonymous caller extends chat entitlement to 14 days using one paid payment ID twice';
end $$;
rollback;
"""
try:
 r=run(sql)
 (ROOT/'tmp/platform-audit/policy-probes.log').write_text(r.stdout+r.stderr,encoding='utf-8')
 print(r.stderr)
 if r.returncode:raise SystemExit(1)
finally:
 run('drop database '+db+' with (force)','postgres')
