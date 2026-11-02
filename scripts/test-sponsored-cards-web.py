"""Fixture browser acceptance for complete sponsored inventory and autoplay."""
import base64,json,os,subprocess,threading,time,urllib.request,uuid
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse,parse_qs
from playwright.sync_api import sync_playwright,expect
ROOT=Path(__file__).resolve().parent.parent
def uid(n):return '10000000-0000-4000-8000-'+str(n).zfill(12)
requests=[];video=b''
ads=[dict(promotion_id=uid(200+n),title=f'Campaign {n}',description='Sponsored fixture',cta_label='Browse listings',target_url='/listings',media_type='video' if n==0 else None,media_path='fixture.mp4' if n==0 else None,thumbnail_path=None,category=None if n<2 else 'house' if n<105 else 'car' if n<107 else 'events') for n in range(109)]
event_rows=[dict(id=uid(500+n),name=f'Event equipment {n}',category_name_en='Chairs',category_name_sw='Viti',public_location_label='Arusha',price_amount_tzs=10000,total_quantity=10,media_paths=[]) for n in range(7)]
class API(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):self.respond()
 def do_POST(self):self.respond()
 def respond(self):
  path=urlparse(self.path).path;q=parse_qs(urlparse(self.path).query);raw=self.rfile.read(int(self.headers.get('Content-Length',0)));args=json.loads(raw or '{}');requests.append((path,args));data=[]
  if self.command=='GET' and '/storage/v1/object/sign/' in path:
   self.send_response(200);self.send_header('Content-Type','video/webm' if video[:4]==bytes.fromhex('1a45dfa3') else 'video/mp4');self.send_header('Content-Length',str(len(video)));self.end_headers();self.wfile.write(video);return
  if path.endswith('/get_public_sponsored_promotions'):
   rows=[row for row in ads if not args.get('p_category_slug') or row['category'] in [None,args['p_category_slug']]]
   offset=args.get('p_offset',0);data=rows[offset:offset+args.get('p_limit',100)]
  elif '/storage/v1/object/sign/' in path:data={'signedURL':'/object/sign/platform-promotions/fixture.mp4?token=fixture'}
  elif path.endswith('/asset_categories'):data=[{'id':uid(1),'slug':'house','name':'House'},{'id':uid(2),'slug':'car','name':'Car'},{'id':uid(3),'slug':'events','name':'Events'}]
  elif path.endswith('/locations'):data=[]
  elif path.endswith('/search_public_listings_v2') or path.endswith('/get_public_home_feed'):
   data=[] if args.get('p_search_text')=='empty' else [dict(listing_id=uid(10+n),title=f'Listing {n}',category_name='House',category_slug='house',public_location_label='Arusha',price_amount=10000,price_period='day',total_count=4,cover_storage_path=None) for n in range(4)]
  elif path.endswith('/get_public_listing_booking_capabilities'):data=[]
  elif path.endswith('/search_public_event_equipment'):data=event_rows
  self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(json.dumps(data).encode())
cache=ROOT/'apps/web/.next/cache/fetch-cache';backup=ROOT/'tmp'/('sponsored-original-cache-'+uuid.uuid4().hex)
if cache.exists():cache.rename(backup)
server=ThreadingHTTPServer(('127.0.0.1',3103),API);threading.Thread(target=server.serve_forever,daemon=True).start()
env={**os.environ,'SUPABASE_URL':'http://127.0.0.1:3103'};log=open(ROOT/'tmp/sponsored-fixture-preview.log','wb')
proc=subprocess.Popen(['node','node_modules/next/dist/bin/next','start','-p','3102'],cwd=ROOT/'apps/web',env=env,stdout=log,stderr=subprocess.STDOUT)
try:
 for _ in range(80):
  try:urllib.request.urlopen('http://127.0.0.1:3102/robots.txt',timeout=2);break
  except Exception:time.sleep(.5)
 with sync_playwright() as pw:
  browser=pw.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
  # MDN's CC0 sample is stored locally; all ad/API/payment behavior remains isolated.
  sample=ROOT/'tmp/sponsored-fixture.webm'
  if not sample.exists():
   sample.write_bytes(urllib.request.urlopen('https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.webm',timeout=30).read())
  video=sample.read_bytes();assert len(video)>100
  for width in [390,1440]:
   ctx=browser.new_context(viewport={'width':width,'height':900});ctx.add_cookies([{'name':'kodimali_language','value':'en','url':'http://127.0.0.1:3102'}]);ctx.add_init_script("localStorage.setItem('kodimali_browser_device_id','audit');localStorage.setItem('kodimali_welcome_seen_v1','audit');localStorage.setItem('kodimali-language','en')")
   events=[];ctx.route('**/rest/v1/rpc/record_platform_promotion_event',lambda route:(events.append(route.request.post_data_json),route.fulfill(status=200,content_type='application/json',body='null')))
   ctx.route('**/rest/v1/rpc/search_public_event_equipment',lambda route:route.fulfill(status=200,content_type='application/json',body=json.dumps(event_rows)))
   ctx.add_init_script("window.__videoErrors=[];document.addEventListener('error',e=>{if(e.target instanceof HTMLMediaElement)window.__videoErrors.push({code:e.target.error?.code,message:e.target.error?.message,src:e.target.currentSrc})},true)")
   page=ctx.new_page();errors=[];page.on('pageerror',lambda error:errors.append(str(error)))
   for path,count in [('/listings',109),('/category/house',105),('/category/car',4),('/listings?category=house',105),('/listings?q=empty&category=car',4),('/events',4)]:
    page.goto('http://127.0.0.1:3102'+path);expect(page.locator('.sponsored-listing-card')).to_have_count(count)
    assert page.get_by_role('button',name='More sponsored ads').count()==0
    assert not page.evaluate('document.documentElement.scrollWidth>innerWidth')
    if path=='/events':
     assert page.locator('#individual-marketplace article').evaluate_all('(els)=>els.slice(0,9).map(e=>e.classList.contains("sponsored-listing-card"))')==[False,False,False,True,False,False,False,True,False]
     expect(page.locator('.sponsored-card-rail > .sponsored-listing-card')).to_have_count(2)
    if path=='/listings':
     assert page.locator('.listing-card').evaluate_all('(els)=>els.slice(0,4).map(e=>e.classList.contains("sponsored-listing-card"))')==[False,False,False,True]
     expect(page.locator('.sponsored-card-rail > .sponsored-listing-card')).to_have_count(count-1)
     rail=page.locator('.sponsored-card-rail');assert rail.evaluate('(el)=>el.scrollWidth>el.clientWidth')
     last=rail.locator('.sponsored-listing-card').last;last.scroll_into_view_if_needed();assert rail.evaluate('(el)=>el.scrollLeft>0')
     ad=page.locator('.sponsored-listing-card').first;ad.scroll_into_view_if_needed();v=ad.locator('video');expect(v).to_have_count(1)
     page.wait_for_function('()=>{const v=document.querySelector(".sponsored-listing-card video");return v && !v.paused && v.currentTime>0}',timeout=20000)
     assert v.evaluate('(v)=>v.muted && v.autoplay && v.loop')
     page.screenshot(path=f'design-previews/listing-location-ads/sponsored-cards-{width}.png')
     page.evaluate('scrollTo(0,document.documentElement.scrollHeight)');page.wait_for_timeout(300);assert v.evaluate('(v)=>v.paused')
    assert not errors,errors
   ctx.close();print('PASS complete inventory, category isolation, empty feeds, mixed cards and muted autoplay:',width,flush=True)
  ctx=browser.new_context(viewport={'width':390,'height':900});user={'id':uid(900),'aud':'authenticated','role':'authenticated','email':'fixture@example.invalid','created_at':'2026-01-01T00:00:00Z'};expiry=int(time.time())+3600
  enc=lambda obj:base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip('=')
  token=enc({'alg':'HS256','typ':'JWT'})+'.'+enc({'sub':user['id'],'exp':expiry,'aud':'authenticated'})+'.fixture'
  storage={'kodimali-language':'en','sb-tlhoajedyaeaaqtrjqqh-auth-token':json.dumps({'access_token':token,'refresh_token':'fixture','token_type':'bearer','expires_in':3600,'expires_at':expiry,'user':user})}
  ctx.add_cookies([{'name':'kodimali_language','value':'en','url':'http://127.0.0.1:3102'}]);ctx.add_init_script('Object.entries('+json.dumps(storage)+').forEach(([key,value])=>localStorage.setItem(key,value))')
  changes=[]
  def admin_api(route):
   path=urlparse(route.request.url).path;data=[]
   if path.endswith('/user_roles'):data=[{'role':'admin'}]
   elif path.endswith('/get_my_admin_permissions'):data=['*']
   elif path.endswith('/platform_promotions'):
    if route.request.method=='PATCH':changes.append(route.request.post_data_json)
    data=[{'id':uid(200),'title':'Fixture ad','target_category_ids':[],'is_active':True,'placement':'global','visibility_scope':'all'}]
   elif path.endswith('/asset_categories'):data=[{'id':uid(1),'name':'House'},{'id':uid(2),'name':'Car'}]
   elif path.endswith('/get_manage_dashboard_counts'):data={}
   route.fulfill(status=200,content_type='application/json',body=json.dumps(data))
  ctx.route('**/rest/v1/**',admin_api);ctx.route('**/auth/v1/user',lambda route:route.fulfill(status=200,content_type='application/json',body=json.dumps(user)))
  page=ctx.new_page();page.goto('http://127.0.0.1:3102/manage/promotions');expect(page.get_by_text('Sponsored categories',exact=True)).to_be_visible(timeout=30000)
  page.get_by_role('checkbox',name='House',exact=True).check();page.get_by_role('checkbox',name='Car',exact=True).check();page.get_by_role('button',name='Save categories',exact=True).click();expect(page.get_by_role('status').filter(has_text='Saved changes.')).to_be_visible()
  assert changes[-1]['target_category_ids']==[uid(1),uid(2)]
  ctx.close();print('PASS administrator assigns multiple categories and saves the exact selection',flush=True)
  browser.close()
 assert any(path.endswith('/get_public_sponsored_promotions') and args.get('p_offset')==100 for path,args in requests)
 print('PASS all 109 campaigns fetched across API pages without truncation',flush=True)
finally:
 proc.terminate()
 try:proc.wait(timeout=10)
 except subprocess.TimeoutExpired:proc.kill();proc.wait()
 server.shutdown();log.close()
 if cache.exists():cache.rename(ROOT/'tmp'/('sponsored-fixture-cache-'+uuid.uuid4().hex))
 if backup.exists():backup.rename(cache)
