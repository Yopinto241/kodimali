"""Run existing SQL regressions in separate disposable localhost databases."""
import json, os, subprocess, uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
ENV={**os.environ,'PGHOST':'127.0.0.1','PGPORT':'55439','PGUSER':'postgres','PGPASSWORD':'','PGCLIENTENCODING':'UTF8'}
PSQL='D:/PostgreSQL/18/bin/psql.exe'
OUT=ROOT/'tmp/platform-audit'; OUT.mkdir(parents=True,exist_ok=True)
def run(args,**kwargs):
    return subprocess.run([PSQL,'-X','-w','-v','ON_ERROR_STOP=1',*args],env=ENV,cwd=ROOT,capture_output=True,text=True,encoding='utf-8',timeout=120,**kwargs)
tests=sorted(ROOT.glob('scripts/test-*.sql'))
tests=[ROOT/'scripts/test-seo-db.sql']+[p for p in tests if p.name not in ['test-seo-db.sql','test-publication-live-transaction.sql'] and not p.name.startswith('test-production-repairs')]
results=[]
for index,path in enumerate(tests):
    db='audit_'+uuid.uuid4().hex[:12]
    if index==1:
        bootstrap="do $$ begin if not exists(select from pg_roles where rolname='anon') then create role anon; end if; if not exists(select from pg_roles where rolname='authenticated') then create role authenticated; end if; if not exists(select from pg_roles where rolname='service_role') then create role service_role bypassrls; end if; end $$;"
        r=run(['-d','postgres','-c',bootstrap]); assert r.returncode==0,r.stderr
    r=run(['-d','postgres','-c','create database '+db]); assert r.returncode==0,r.stderr
    try:
        if path.name=='test-seo-db.sql':
            source=path.read_text(encoding='utf-8')
            for role in ['anon','authenticated']:
                source=source.replace('create role '+role+';',"do $$ begin if not exists(select from pg_roles where rolname='"+role+"') then create role "+role+"; end if; end $$;")
            import re
            source=re.sub(r'(?m)^\\ir (.+)$',lambda m:'\\ir '+(path.parent/m.group(1)).resolve().as_posix(),source)
            r=run(['-d',db,'-f','-'],input=source)
        else:
            r=run(['-d',db,'-f',str(path)])
        (OUT/(path.stem+'.log')).write_text(r.stdout+r.stderr,encoding='utf-8')
        results.append({'test':path.name,'passed':r.returncode==0})
        print(('PASS ' if r.returncode==0 else 'FAIL ')+path.name,flush=True)
        if r.returncode: print(r.stderr[-900:],flush=True)
    finally:
        run(['-d','postgres','-c','drop database '+db+' with (force)'])
(OUT/'sql-results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
