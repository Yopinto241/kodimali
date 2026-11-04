"""Read-only production control snapshot/comparison. Never applies migrations."""
import argparse,json,os,subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compare',type=Path)
parser.add_argument('--output',type=Path,default=ROOT/'tmp/repair-release-controls.json')
args=parser.parse_args()
if (ROOT/'supabase/.temp/project-ref').read_text().strip()!='tlhoajedyaeaaqtrjqqh':raise SystemExit('The linked project does not match this repair release.')
cli=os.environ.get('SUPABASE_CLI','supabase')
query="""begin read only;
select jsonb_build_object(
 'project','tlhoajedyaeaaqtrjqqh',
 'settings',(select to_jsonb(s)-'updated_at'-'updated_by'-'created_at' from public.marketplace_settings s where id=true),
 'feature_flags',(select jsonb_object_agg(key,jsonb_build_object('enabled',enabled,'configuration',configuration)) from public.kodimali_feature_flags)
) as controls;commit;"""
query_file=ROOT/'tmp/repair-control-check.sql'
query_file.parent.mkdir(parents=True,exist_ok=True)
query_file.write_text(query,encoding='utf-8')
result=subprocess.run([cli,'db','query','--linked','--file',str(query_file),'-o','json'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',timeout=60)
if result.returncode:raise SystemExit('Read-only control check failed; no action taken.')
raw=result.stdout
# CLI diagnostics can precede its structured JSON envelope.
start=raw.find('{')
try:
    document=json.JSONDecoder().raw_decode(raw[start:])[0]
    snapshot=document['rows'][0]['controls']
except (ValueError,KeyError,IndexError):raise SystemExit('Unexpected read-only response; no action taken.')
if args.compare and json.loads(args.compare.read_text(encoding='utf-8'))!=snapshot:
    raise SystemExit('Administrative controls differ from the supplied snapshot. Preserve current controls and review the difference before continuing deployment.')
args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(json.dumps(snapshot,sort_keys=True,indent=2)+'\n',encoding='utf-8')
print('PASS: read-only control snapshot'+(' matches baseline' if args.compare else ' recorded')+'. No production mutations.')
