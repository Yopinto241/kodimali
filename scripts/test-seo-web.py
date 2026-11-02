"""Production-build HTTP/HTML integration tests with an isolated, read-only public API fixture proxy.
No fixture is inserted into Supabase. Start after the web production build.
"""
import json,os,subprocess,threading,time,urllib.request,urllib.error,uuid,xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse,parse_qs
import importlib.util
_spec=importlib.util.spec_from_file_location("audit_seo",Path(__file__).with_name("audit-seo.py"));_audit=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(_audit)
HTML,NoRedirect,AGENTS=_audit.HTML,_audit.NoRedirect,_audit.AGENTS

ROOT=Path(__file__).resolve().parent.parent; BASE='http://127.0.0.1:3102'; LIVE='https://tlhoajedyaeaaqtrjqqh.supabase.co'
E='11111111-1111-4111-8111-111111111111';S='22222222-2222-4222-8222-222222222222';L='363d0a72-7151-4cbd-a037-c89daa03c499'
equipment={'id':E,'name':'Viti vya sherehe SEO fixture','description':'Viti safi vya kukodisha kwa sherehe.','total_quantity':100,'price_amount_tzs':1000,'price_unit':'item_day','public_location_label':'Dar es Salaam','media_paths':[],'event_equipment_categories':{'name_sw':'Viti','name_en':'Chairs'}}
service={'id':S,'title':'Mpiga picha SEO fixture','description':'Huduma ya picha kwa matukio.','pricing_mode':'custom_quote','price_amount_tzs':None,'event_service_profiles':{'id':S,'display_name':'Public provider','provider_kind':'photographer','portfolio_media':[],'experience_years':3}}
RPCS={'contact_payments_enabled','get_active_platform_promotions','search_public_listings_v2','get_public_listings','get_public_home_feed','get_public_listing_detail','get_public_listing_booking_capability','get_public_listing_booking_capabilities','get_public_agent_profile','get_active_featured_listing_ids','get_public_promotions'}
requests=[];outage=False
class Proxy(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  try:self.handle_request()
  except (BrokenPipeError,ConnectionResetError):pass
 def do_POST(self):self.do_GET()
 def handle_request(self):
  global outage
  path=urlparse(self.path).path;body=self.rfile.read(int(self.headers.get('Content-Length','0')));params=parse_qs(urlparse(self.path).query);requests.append((path,body))
  data=None;status=200
  if path.endswith('/get_public_seo_sitemap'):
   if outage:self.send_response(503);self.end_headers();self.wfile.write(b'Unavailable');return
   p=json.loads(body);kind=p['p_kind'];ids=([L]+[str(uuid.UUID(int=n+1)) for n in range(1000)]) if kind=='listings' else [E] if kind=='equipment' else [S]
   data={'total_count':len(ids),'entries':[{'id':id,'updated_at':'2026-10-20T10:00:00Z'} for id in ids[p['p_offset']:p['p_offset']+p['p_limit']]]}
  elif path.endswith('/search_public_event_equipment'):data=[equipment]
  elif path.endswith('/search_public_event_services'):data=[{**service,'offering_id':S}]
  elif path.endswith('/event_equipment_items') or path.endswith('/event_service_offerings'):
   id=params.get('id',[''])[0];data=[equipment if path.endswith('/event_equipment_items') else service] if id in ['eq.'+E,'eq.'+S] else []
   assert params.get('publication_status')==['eq.published'];assert params.get('is_active')==['eq.true']
  if data is not None:
   self.send_response(status);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(json.dumps(data).encode());return
  # Only public table reads, public read RPCs, or anonymous storage signing may reach the real service.
  allowed=self.command=='GET' or (path.startswith('/rest/v1/rpc/') and path.rsplit('/',1)[-1] in RPCS) or path.startswith('/storage/v1/object/sign/')
  if not allowed:self.send_response(405);self.end_headers();return
  headers={k:v for k,v in self.headers.items() if k.lower() in ['authorization','apikey','content-type','prefer']}
  try:r=urllib.request.urlopen(urllib.request.Request(LIVE+self.path,data=body if self.command=='POST' else None,headers=headers,method=self.command),timeout=30)
  except urllib.error.HTTPError as e:r=e
  payload=r.read();self.send_response(r.status);self.send_header('Content-Type',r.headers.get('Content-Type','application/json'));self.end_headers();self.wfile.write(payload)

def fetch(path,headers=None):
 req=urllib.request.Request(BASE+path,headers={'User-Agent':AGENTS['googlebot'],**(headers or {})})
 try:r=urllib.request.build_opener(NoRedirect()).open(req,timeout=45)
 except urllib.error.HTTPError as e:r=e
 raw=r.read();p=HTML();
 if 'text/html' in r.headers.get('Content-Type',''):p.feed(raw.decode('utf-8'))
 return r,raw,p

# Next's persistent fetch cache is shared by production preview processes. Isolate fixture values and restore the original cache after this test. Do not run another production preview concurrently.
cache_path=ROOT/'apps/web/.next/cache/fetch-cache';cache_backup=ROOT/'tmp'/('seo-original-cache-'+uuid.uuid4().hex)
if cache_path.exists():cache_path.rename(cache_backup)
server=ThreadingHTTPServer(('127.0.0.1',3103),Proxy);threading.Thread(target=server.serve_forever,daemon=True).start()
env={**os.environ,'SUPABASE_URL':'http://127.0.0.1:3103'};log=(ROOT/'tmp/seo-fixture-preview.log').open('w',encoding='utf-8')
proc=subprocess.Popen(['node','node_modules/next/dist/bin/next','start','--hostname','127.0.0.1','--port','3102'],cwd=ROOT/'apps/web',env=env,stdout=log,stderr=log,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
checks=[]
def passed(name):checks.append(name);print('PASS',name,flush=True)
try:
 for n in range(60):
  try:r,raw,p=fetch('/robots.txt');break
  except Exception:time.sleep(.5)
 else:raise RuntimeError('Fixture preview did not start')
 assert b'Sitemap: https://kodimali.com/sitemap.xml' in raw and b'Disallow: /api/' in raw;passed('robots allows public content and references official sitemap')
 for path in ['/','/listings','/category/house','/events','/toa-taarifa','/privacy','/safety','/terms','/advertise','/download','/delete-account',f'/listing/{L}',f'/events/equipment/{E}',f'/events/service/{S}']:
  r,raw,p=fetch(path);assert r.status==200,(path,r.status);assert len(p.canon)==1 and p.canon[0].rstrip('/')==('https://kodimali.com'+path).rstrip('/'),(path,p.canon);assert p.meta.get('description') and p.meta.get('og:image') and p.meta.get('twitter:card')=='summary_large_image',path
  assert p.title.count('KODIMALI')==1,(path,p.title);assert p.h1,path;assert p.lang=='sw';assert 'noindex' not in p.meta.get('robots','');assert all(not isinstance(x,dict) or not x.get('parse_error') for x in p.schemas),path
 passed('14 public pages have canonical, unique-brand metadata, social images, H1, language and parseable JSON-LD')
 for path in ['/account','/account/chat/test','/admin','/agent','/owner','/manage','/login','/register','/compare','/map','/events/plan',f'/listing/{L}/book',f'/listing/{L}/chat',f'/listing/{L}/contact']:
  r,raw,p=fetch(path);assert 'noindex' in r.headers.get('X-Robots-Tag',''),path;assert 'noindex' in p.meta.get('robots',''),path
 passed('14 private and low-value routes have both noindex metadata and response headers')
 for path,canonical in [('/listings?minPrice=1000','/listings'),('/category/house?q=test','/category/house'),('/?regionId=11111111-1111-4111-8111-111111111111','/'),('/events?kind=service','/events')]:
  r,raw,p=fetch(path);assert 'noindex' in p.meta.get('robots',''),path;assert len(p.canon)==1 and p.canon[0].rstrip('/')==('https://kodimali.com'+canonical).rstrip('/'),(path,p.canon)
 r,raw,p=fetch('/listings?page=2');assert p.canon==['https://kodimali.com/listings?page=2'];passed('filters noindex, canonical consolidation and pagination')
 for path in ['/category/no-such-category','/listing/00000000-0000-0000-0000-000000000000','/listing/not-an-id','/events/equipment/00000000-0000-0000-0000-000000000000','/events/service/not-an-id']:
  r,raw,p=fetch(path);assert r.status==404,(path,r.status);assert 'noindex' in p.meta.get('robots',''),path
 passed('missing and invalid public items/categories return HTTP 404 and noindex')
 for headers in [{'Host':'www.kodimali.com'},{'Host':'kodimali.com','X-Forwarded-Proto':'http'}]:
  r,raw,p=fetch('/events?test=preserved',headers);assert r.status==308 and r.headers['Location']=='https://kodimali.com/events?test=preserved',dict(r.headers)
 r,raw,p=fetch('/category/events');assert r.status==308 and r.headers['Location']=='/events';passed('permanent www/HTTP redirects preserve path and query; events category consolidates')
 ns={'s':'http://www.sitemaps.org/schemas/sitemap/0.9'};r,raw,p=fetch('/sitemap.xml');assert r.status==200;tree=ET.fromstring(raw);assert tree.tag.endswith('urlset'),tree.tag
 items=tree.findall('s:url',ns);urls=[e.find('s:loc',ns).text for e in items]
 assert len([u for u in urls if '/listing/' in u])==1001
 assert len(set(urls))==len(urls);assert 'https://kodimali.com/listing/'+L in urls;assert 'https://kodimali.com/events/equipment/'+E in urls;assert 'https://kodimali.com/events/service/'+S in urls
 assert 'https://kodimali.com/events' in urls and 'https://kodimali.com/toa-taarifa' in urls
 assert not any(any(x in urlparse(u).path.split('/') for x in ['account','manage','admin','login','register','book','contact','chat','plan']) or '?' in u for u in urls)
 for item in items:
  path=urlparse(item.find('s:loc',ns).text).path
  lastmod=item.find('s:lastmod',ns)
  if '/listing/' in path or '/events/equipment/' in path or '/events/service/' in path:assert lastmod is not None and lastmod.text=='2026-10-20T10:00:00Z'
  else:assert lastmod is None
 passed('existing flat XML urlset parses; 1001 approved listings, Events/Toa Taarifa, true dates, no private URLs or duplicates')
 r,raw,p=fetch('/opengraph-image');assert r.status==200 and raw.startswith(b'\x89PNG');passed('official-logo social image is a real PNG')
 from playwright.sync_api import sync_playwright,expect
 with sync_playwright() as pw:
  browser=pw.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe');context=browser.new_context(java_script_enabled=False,viewport={'width':390,'height':844});page=context.new_page()
  for path,title in [(f'/events/equipment/{E}',equipment['name']),(f'/events/service/{S}',service['title'])]:
   page.goto(BASE+path);expect(page.get_by_role('heading',name=title,exact=True)).to_be_visible();expect(page.get_by_text(equipment['description'] if 'equipment' in path else service['description'],exact=True)).to_be_visible()
   assert page.locator('script[type="application/ld+json"]').count()>=2
  page.goto(BASE+'/events');expect(page.get_by_text(equipment['name'],exact=True)).to_be_visible();assert page.locator(f'a[href="/events/equipment/{E}"]').count()
  browser.close()
 passed('Events catalog and both detail types remain readable and linked with JavaScript disabled')
 Path('tmp/seo-web-test-results.json').write_text(json.dumps({'passed':checks,'public_sitemap_urls':len(urls)},indent=2),encoding='utf-8')
finally:
 proc.terminate()
 try:proc.wait(timeout=10)
 except subprocess.TimeoutExpired:proc.kill();proc.wait()
 server.shutdown();log.close()
 if cache_path.exists():cache_path.rename(ROOT/'tmp'/('seo-fixture-cache-'+uuid.uuid4().hex))
 if cache_backup.exists():cache_backup.rename(cache_path)
