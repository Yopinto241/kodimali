"""Read-only platform audit. Credentials remain inside child-process environments."""
import json, os, re, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLI = Path('D:/node-v24.16.0-win-x64/node-v24.16.0-win-x64/node_cache/_npx/b96a6bd565c470ce/node_modules/@supabase/cli-windows-x64/bin/supabase.exe')
OUT = ROOT / 'tmp/platform-audit'
OUT.mkdir(parents=True, exist_ok=True)

def cli(*args):
    result = subprocess.run([str(CLI), *args], cwd=ROOT, capture_output=True, text=True, encoding='utf-8', timeout=180)
    if result.returncode:
        raise RuntimeError('Supabase CLI failed: ' + ' '.join(args[:3]))
    return result.stdout

dump = cli('db', 'dump', '--linked', '--schema', 'public', '--dry-run')
env = os.environ.copy()
for key, value in re.findall(r'^export (PG\w+)="([^"\n]*)"', dump, re.M):
    env[key] = value
env['PGOPTIONS'] = '-c default_transaction_read_only=on -c statement_timeout=30000'
env['PGCLIENTENCODING'] = 'UTF8'
query = """
begin read only;
set local role postgres;
select json_build_object(
 'functions', (select json_agg(json_build_object('name',p.proname,'arguments',pg_get_function_arguments(p.oid),'result',pg_get_function_result(p.oid),'security_definer',p.prosecdef,'anon_execute',has_function_privilege('anon',p.oid,'execute'),'authenticated_execute',has_function_privilege('authenticated',p.oid,'execute'),'definition',pg_get_functiondef(p.oid))) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f'),
 'tables', (select json_agg(json_build_object('name',c.relname,'rls',c.relrowsecurity,'kind',c.relkind,'anon_select',has_table_privilege('anon',c.oid,'select'),'anon_insert',has_table_privilege('anon',c.oid,'insert'),'anon_update',has_table_privilege('anon',c.oid,'update'),'authenticated_select',has_table_privilege('authenticated',c.oid,'select'))) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v')),
 'policies', (select json_agg(p) from pg_policies p where schemaname='public'),
 'migrations', (select json_agg(version order by version) from supabase_migrations.schema_migrations),
 'extensions', (select json_agg(extname) from pg_extension),
 'columns', (select json_agg(json_build_object('table',table_name,'column',column_name,'type',data_type)) from information_schema.columns where table_schema='public'),
 'storage_buckets', (select json_agg(json_build_object('id',id,'public',public,'file_size_limit',file_size_limit,'allowed_mime_types',allowed_mime_types)) from storage.buckets)
 , 'feature_flags', (select json_agg(json_build_object('key',key,'enabled',enabled)) from public.kodimali_feature_flags)
 , 'payment_switches', (select json_agg(json_build_object('contact',contact_payments_enabled,'chat',chat_payments_enabled,'publication',agent_listing_payments_enabled,'subscriptions',subscription_payments_enabled,'boosts',listing_boost_payments_enabled,'booking',booking_payments_enabled,'events',event_payments_enabled,'chat_price',paid_chat_unlock_amount_tzs)) from public.marketplace_settings)
 , 'push_queue_summary', (select json_agg(s) from (select status,count(*) total,max(attempt_count) maximum_attempts,count(*) filter(where terminal_at is null and created_at<now()-interval '1 hour') nonterminal_older_than_hour from public.notification_delivery_outbox group by status) s)
 , 'triggers', (select json_agg(json_build_object('table',c.relname,'name',t.tgname,'definition',pg_get_triggerdef(t.oid))) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal)
);
rollback;
"""
r = subprocess.run(['D:/PostgreSQL/18/bin/psql.exe','-X','-q','-t','-A','-v','ON_ERROR_STOP=1','-f','-'],input=query,cwd=ROOT,env=env,capture_output=True,text=True,encoding='utf-8',timeout=180)
if r.returncode:
    raise RuntimeError('Read-only catalog query failed: ' + r.stderr[-1500:])
catalog = json.loads(r.stdout)
(OUT/'live-catalog.json').write_text(json.dumps(catalog,indent=2),encoding='utf-8')
functions = json.loads(cli('functions','list','--project-ref','tlhoajedyaeaaqtrjqqh','--output','json'))
(OUT/'live-functions.json').write_text(json.dumps(functions,indent=2),encoding='utf-8')
known = {f['name'] for f in catalog['functions']}
missing = {}
for directory in ['apps/customer_mobile/lib','apps/manage_mobile/lib','apps/web/src','supabase/functions']:
    calls = {}
    for path in (ROOT/directory).rglob('*'):
        if path.suffix not in ['.dart','.ts','.tsx']: continue
        if '.test.' in path.name: continue
        for name in re.findall(r'\.rpc(?:<[^;]*?>)?\(\s*[\'\"]([a-z_][a-z_0-9]*)[\'\"]',path.read_text(encoding='utf-8')):
            calls.setdefault(name,[]).append(str(path.relative_to(ROOT)))
    missing[directory] = {k:v for k,v in calls.items() if k not in known}
(OUT/'missing-rpcs.json').write_text(json.dumps(missing,indent=2),encoding='utf-8')
print('Read-only catalog:',len(catalog['tables']),'tables/views,',len(known),'function names,',len(catalog['policies']),'RLS policies')
print('Missing literal RPCs:',json.dumps(missing))
print('Tables without RLS:',json.dumps([t for t in catalog['tables'] if t['kind'] in ['r','p'] and not t['rls']]))
print('Catalog evidence saved under tmp/platform-audit; contains schema metadata only.')
