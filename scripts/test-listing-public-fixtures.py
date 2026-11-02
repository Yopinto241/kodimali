"""Run browser acceptance checks against an isolated read-only public API fixture."""
import json,os,subprocess,threading,time,urllib.request,uuid
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse,parse_qs
ROOT=Path(__file__).resolve().parent.parent
def uid(n):return '10000000-0000-4000-8000-'+str(n).zfill(12)
locations=[{'id':uid(1),'name':'Tanzania','location_type':'country','parent_id':None},{'id':uid(2),'name':'Arusha','location_type':'region','parent_id':uid(1)},{'id':uid(3),'name':'Dar es Salaam','location_type':'region','parent_id':uid(1)}]
listings=[dict(listing_id=uid(100+n),title=f'Fixture listing {n}',public_location_label='Arusha',price_amount=10000,price_period='day',category_name='House',category_slug='house',cover_storage_path=None,total_count=6) for n in range(6)]
requests=[]
class API(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):self.respond()
 def do_POST(self):self.respond()
 def respond(self):
  path=urlparse(self.path).path;query=parse_qs(urlparse(self.path).query);body=self.rfile.read(int(self.headers.get('Content-Length',0)));data=[]
  args=json.loads(body or '{}');requests.append((path,args))
  if path.endswith('/locations'):
   data=locations
   for key in ['location_type','parent_id','id']:
    if key in query:data=[row for row in data if row.get(key)==(None if query[key][0]=='is.null' else query[key][0].removeprefix('eq.'))]
  elif path.endswith('/asset_categories'):data=[dict(id=uid(10),name='House',slug='house',display_order=1)]
  elif path.endswith('/search_public_listings_v2') or path.endswith('/get_public_listings'):data=listings if not args.get('p_search_text') else []
  elif path.endswith('/get_public_listing_booking_capabilities'):data=[dict(listing_id=row['listing_id'],capability={'effective_mode':'request_booking','has_whatsapp':index%2==0}) for index,row in enumerate(listings)]
  elif path.endswith('/get_public_listing_detail'):data=[{**listings[0],'description':'Public fixture description','agent_id':uid(50),'agent_display_name':'Fixture agent','agent_phone_number':None,'agent_verification_status':'approved','media':[],'listing_attributes':{}}]
  elif path.endswith('/get_active_platform_promotions'):data=[dict(promotion_id=uid(200+n),title='Fixture sponsored ad '+str(n),description='Compact promotion description',cta_label=None,target_url=None,media_type='image',media_path='fixture.png',thumbnail_path=None) for n in range(2)]
  elif '/storage/v1/object/sign/' in path:data={'signedURL':'/object/sign/platform-promotions/fixture.png?token=fixture'}
  elif path.endswith('/contact_payments_enabled'):data=True
  self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(json.dumps(data).encode())
cache=ROOT/'apps/web/.next/cache/fetch-cache';backup=ROOT/'tmp'/('listing-original-cache-'+uuid.uuid4().hex)
if cache.exists():cache.rename(backup)
server=ThreadingHTTPServer(('127.0.0.1',3103),API);threading.Thread(target=server.serve_forever,daemon=True).start()
env={**os.environ,'SUPABASE_URL':'http://127.0.0.1:3103','LISTING_TEST_BASE':'http://127.0.0.1:3102'}
log=open(ROOT/'tmp/listing-fixture-preview.log','wb')
proc=subprocess.Popen(['node','node_modules/next/dist/bin/next','start','-p','3102'],cwd=ROOT/'apps/web',env=env,stdout=log,stderr=subprocess.STDOUT)
try:
 for _ in range(60):
  try:
   urllib.request.urlopen('http://127.0.0.1:3102/robots.txt',timeout=2);break
  except Exception:time.sleep(.5)
 result=subprocess.run(['python','scripts/test-listing-location-ads.py'],cwd=ROOT,env=env)
 Path(ROOT/'tmp/listing-fixture-requests.json').write_text(json.dumps(requests,indent=2),encoding='utf-8')
 if result.returncode:raise SystemExit(result.returncode)
 assert any(path.endswith('/get_active_platform_promotions') and args.get('p_selected_region_id') for path,args in requests),'Selected location reaches the ad RPC'
 print('PASS selected location targets ads; fixture reads never reach Supabase',flush=True)
finally:
 proc.terminate()
 try:proc.wait(timeout=10)
 except subprocess.TimeoutExpired:proc.kill();proc.wait()
 server.shutdown();log.close()
 if cache.exists():cache.rename(ROOT/'tmp'/('listing-fixture-cache-'+uuid.uuid4().hex))
 if backup.exists():backup.rename(cache)
