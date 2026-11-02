"""Run Events behavior tests against an isolated local PostgreSQL database.

Requires PostgreSQL on 127.0.0.1:55439 (never accepts a remote host).
The test harness stubs shared auth/account prerequisites, then installs the real
Events migrations and real payment functions. It does not contact Supabase.
"""
import os
import re
import subprocess
import tempfile
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PSQL = os.environ.get('EVENT_TEST_PSQL', 'psql')
DATABASE = 'events_test_' + uuid.uuid4().hex[:12]
ENV = {**os.environ, 'PGHOST': '127.0.0.1', 'PGPORT': '55439', 'PGUSER': 'postgres', 'PGPASSWORD': '', 'PGCLIENTENCODING': 'UTF8'}

def run(sql, database=DATABASE):
    result = subprocess.run([PSQL, '-X', '-w', '-v', 'ON_ERROR_STOP=1', '-d', database], input=sql, text=True, encoding='utf-8', capture_output=True, env=ENV)
    if result.returncode:
        raise RuntimeError(result.stdout[-3000:] + result.stderr[-6000:])
    if "PASS:" in result.stderr:
        print("\n".join(line for line in result.stderr.splitlines() if "PASS:" in line))
    return result.stdout

def source(name):
    return (ROOT / 'supabase/migrations' / name).read_text(encoding='utf-8')

def function(sql, name):
    start = sql.index('create or replace function public.' + name + '(')
    body = sql.index('$$', start)
    end = sql.index('$$;', body + 2) + 3
    return sql[start:end]

BOOTSTRAP = r"""
create schema auth; create schema storage;
do $$ begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
end $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function auth.role() returns text language sql stable as $$ select current_setting('request.jwt.claim.role',true) $$;
create table public.profiles(id uuid primary key default gen_random_uuid());
create table public.test_permissions(user_id uuid,permission text);
create function public.has_admin_permission(p_permission text) returns boolean language sql stable security definer as $$ select exists(select 1 from public.test_permissions where user_id=auth.uid() and permission in(p_permission,'*')) $$;
create function public.is_admin() returns boolean language sql stable security definer as $$ select public.has_admin_permission('*') or public.has_admin_permission('events.manage') $$;
create table public.owner_profiles(id uuid primary key default gen_random_uuid(),profile_id uuid references public.profiles(id),verification_status text);
create function public.current_owner_id() returns uuid language sql stable security definer as $$ select id from public.owner_profiles where profile_id=auth.uid() and verification_status='verified' limit 1 $$;
create table public.admin_role_definitions(id text primary key,name text,description text,permissions jsonb,rank integer,is_active boolean default true);
create table public.asset_categories(id uuid primary key default gen_random_uuid(),name text,slug text unique,description text,icon_key text,display_order integer,is_active boolean);
create table public.locations(id uuid primary key default gen_random_uuid());
create table public.rental_information_submissions(id uuid primary key default gen_random_uuid());
create table public.notifications(id uuid primary key default gen_random_uuid(),user_id uuid,type text,title text,body text,payload jsonb);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
alter table storage.objects enable row level security;
create table public.marketplace_settings(id boolean primary key,event_payments_enabled boolean,event_deposit_percent integer);
insert into public.marketplace_settings values(true,true,25);
create table public.test_feature_flags(key text primary key,enabled boolean);
insert into public.test_feature_flags values('event_deposit_payments',true),('event_balance_payments',true);
create function public.kodimali_feature_enabled(p_key text) returns boolean language sql stable as $$ select coalesce((select enabled from public.test_feature_flags where key=p_key),false) $$;
create function public.resolve_booking_hold_minutes(uuid,text) returns integer language sql as $$ select 30 $$;
create function public.calculate_booking_split(bigint,integer) returns table(deposit_minor bigint,balance_minor bigint) language sql as $$ select ($1*$2+50)/100,$1-($1*$2+50)/100 $$;
create table public.booking_requests(id uuid,customer_id uuid,listing_id uuid,requested_start_at timestamptz,requested_end_at timestamptz);
create table public.booking_terms_snapshots(id uuid primary key);
"""

PAYMENT_SUPPORT = r"""
alter table public.platform_payment_orders add column payment_intent_id uuid references public.payment_intents(id);
alter table public.event_payment_obligations add column payment_order_id uuid references public.platform_payment_orders(id);
alter table public.event_payment_obligations drop constraint event_payment_obligations_collection_enabled_check;
alter table public.event_plans drop constraint event_plans_status_check;
alter table public.event_plans add check(status in('draft','quote_requested','provider_review','partially_confirmed','fully_confirmed','agreement_pending','payment_pending','confirmed','in_progress','completed','cancelled','disputed'));
create table public.financial_accounts(id uuid primary key default gen_random_uuid(),code text);
insert into public.financial_accounts(code) values('CASH_PROVIDER_CLEARING'),('BOOKING_COLLECTIONS_LIABILITY');
create table public.financial_journals(id uuid primary key default gen_random_uuid(),journal_type text,reference_type text,reference_id uuid,idempotency_key text,description text,posted_by uuid,metadata jsonb);
create table public.financial_postings(journal_id uuid,account_id uuid,debit_minor bigint,credit_minor bigint,memo text);
create table public.financial_reconciliation_cases(id uuid primary key default gen_random_uuid(),provider text,provider_transaction_id text,provider_order_id text,payment_intent_id uuid,reported_amount_minor bigint,currency text,reason text,status text default 'open',resolution text,resolved_by uuid,resolved_at timestamptz);
"""

try:
    run('create database ' + DATABASE, 'postgres')
    run(BOOTSTRAP)
    run(source('20261024160000_kodimali_events_foundation.sql'))
    run(source('20261024170000_event_public_catalog_individual_bookings.sql'))
    unified = source('20261025213000_unified_sonicpesa_checkout.sql')
    start = unified.index('create table if not exists public.platform_payment_orders')
    run(unified[start:unified.index('create index',start)])
    finance = source('20261026170000_kodimali_3_financial_core.sql')
    start = finance.index('create table if not exists public.payment_intents')
    run(finance[start:finance.index('alter table public.platform_payment_orders',start)])
    # The typed Events migration widens this enum constraint in production.
    run("alter table public.payment_intents drop constraint payment_intents_product_check;" + PAYMENT_SUPPORT)
    run(function(source('20261026360000_kodimali_3_configurable_inventory_hold.sql'),'prepare_event_payment_intent'))
    run(function(source('20261026210000_kodimali_3_booking_payment_intents.sql'),'finalize_platform_payment'))
    run(source('20261029140000_events_workflow_repairs.sql'))
    run(source('20261029141000_events_recovery_workflows.sql'))
    run(source('20261029143000_event_payment_terms_consistency.sql'))
    run('grant usage on schema public,auth,storage to authenticated,anon,service_role; grant all on all tables in schema public to authenticated; grant select,insert,update,delete on storage.objects to authenticated; grant usage,select on all sequences in schema public to authenticated;')
    run((ROOT/'supabase/tests/042_events_workflow_repairs.sql').read_text(encoding='utf-8'))
    for kind in ['equipment', 'service']:
        run("""
          insert into public.event_plans(id,customer_id,event_type_id,event_period,attendance)
          select ('50000000-0000-0000-0000-'||lpad(x::text,12,'0'))::uuid,
          '00000000-0000-0000-0000-000000000002',(select id from public.event_types where slug='wedding'),
          tstzrange(now()+interval '25 days',now()+interval '25 days 2 hours','[)'),1 from generate_series(1,2) x;
        """)
        if kind == 'equipment':
            run("insert into public.event_plan_items(id,plan_id,item_kind,equipment_id,requested_quantity) select ('60000000-0000-0000-0000-'||lpad(x::text,12,'0'))::uuid,('50000000-0000-0000-0000-'||lpad(x::text,12,'0'))::uuid,'equipment','20000000-0000-0000-0000-000000000003',60 from generate_series(1,2) x")
        else:
            run("insert into public.event_plan_items(id,plan_id,item_kind,offering_id) select ('60000000-0000-0000-0000-'||lpad(x::text,12,'0'))::uuid,('50000000-0000-0000-0000-'||lpad(x::text,12,'0'))::uuid,'service','40000000-0000-0000-0000-000000000004' from generate_series(1,2) x")

        def confirm(index):
            actor = '00000000-0000-0000-0000-00000000000' + ('3' if kind == 'equipment' else '4')
            function_name = 'confirm_event_equipment_item' if kind == 'equipment' else 'confirm_event_service_item'
            item = '60000000-0000-0000-0000-' + str(index).zfill(12)
            statement = f"begin; set role authenticated; select set_config('request.jwt.claim.role','authenticated',true); select set_config('request.jwt.claim.sub','{actor}',true); select public.{function_name}('{item}'); select pg_sleep(0.4); commit;"
            return subprocess.run([PSQL,'-X','-w','-v','ON_ERROR_STOP=1','-d',DATABASE],input=statement,text=True,capture_output=True,env=ENV)

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(confirm,[1,2]))
        assert sum(r.returncode==0 for r in results)==1, '\n'.join(r.stderr for r in results)
        assert any('Insufficient equipment' in r.stderr or 'Provider is unavailable' in r.stderr for r in results)
        print('PASS: concurrent',kind,'requests cannot overbook')
        # Only disposable test plans are removed, never user data.
        run("delete from public.event_plans where id in ('50000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000002')")
    print('Events behavioral SQL checks passed.')
finally:
    if os.environ.get('EVENT_TEST_KEEP_DB') == '1':
        print('Retained local test database:',DATABASE)
    else:
        run('drop database if exists ' + DATABASE + ' with (force)', 'postgres')
