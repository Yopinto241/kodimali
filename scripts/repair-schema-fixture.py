"""Restore a metadata-only snapshot to a NEW localhost database and apply repairs.

Requires tmp/repair-baseline/schema.sql, exported read-only with pg_dump --schema-only
--no-owner --schema=public --schema=auth --schema=storage --role=postgres.
Never accepts a production target. No customer data is exported/restored.
"""
import json,os,re,subprocess,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
DB='repair_fixture_20261104_'+uuid.uuid4().hex[:8]
ENV={**os.environ,'PGHOST':'127.0.0.1','PGPORT':'55439','PGUSER':'postgres','PGPASSWORD':'','PGCLIENTENCODING':'UTF8'}
OUT=ROOT/'tmp/repair-tests';OUT.mkdir(parents=True,exist_ok=True)
def run(sql,database=DB):
 return subprocess.run(['D:/PostgreSQL/18/bin/psql.exe','-X','-w','-v','ON_ERROR_STOP=1','-d',database,'-f','-'],input=sql,env=ENV,cwd=ROOT,capture_output=True,text=True,encoding='utf-8',timeout=180)
existing=run("select 1 from pg_database where datname='"+DB+"'",'postgres')
if re.search(r'^\s*1\s*$',existing.stdout,re.M):raise SystemExit('Fixture already exists: choose a fresh DB name in this local-only script; do not overwrite it.')
r=run('create database '+DB,'postgres');assert r.returncode==0,r.stderr
roles=['anon','authenticated','service_role','dashboard_user','supabase_admin','supabase_auth_admin','supabase_storage_admin']
bootstrap=''
for role in roles:
 bootstrap+="do $$ begin if not exists(select from pg_roles where rolname='"+role+"') then create role "+role+(" bypassrls" if role=='service_role' else '')+"; end if; end $$;\n"
bootstrap+='''alter role service_role bypassrls;
drop schema public;
create schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;
create schema net;
create function net.http_post(url text,body jsonb default '{}'::jsonb,params jsonb default '{}'::jsonb,headers jsonb default '{}'::jsonb,timeout_milliseconds integer default 1000) returns bigint language sql as $$ select 1::bigint $$;
create schema vault;
create table vault.decrypted_secrets(name text,decrypted_secret text);
'''
schema=(ROOT/'tmp/repair-baseline/schema.sql').read_text(encoding='utf-8')
r=run(bootstrap+schema)
(OUT/'schema-restore.log').write_text(r.stdout+r.stderr,encoding='utf-8')
if r.returncode:print(r.stderr[-1800:]);raise SystemExit(1)
print('Restored metadata-only public/auth/storage schema.',flush=True)
for path in sorted((ROOT/'supabase/migrations').glob('20261104*.sql')):
 r=run('begin;\n'+path.read_text(encoding='utf-8')+'\ncommit;')
 (OUT/(path.stem+'.log')).write_text(r.stdout+r.stderr,encoding='utf-8')
 print(('PASS ' if r.returncode==0 else 'FAIL ')+path.name,flush=True)
 if r.returncode:print(r.stderr[-2000:]);raise SystemExit(1)
print('All repair migrations applied transactionally to '+DB)
(OUT/'database.txt').write_text(DB,encoding='utf-8')
