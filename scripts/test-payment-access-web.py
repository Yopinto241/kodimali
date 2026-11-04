"""Payment-access UX acceptance; every checkout/Auth call is intercepted."""
import base64,json,os,re,time
from urllib.request import Request,urlopen
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('ACCESS_WEB_BASE','http://localhost:3101')
html=urlopen(Request('https://kodimali.com/',headers={'User-Agent':'Mozilla/5.0'}),timeout=30).read().decode()
LISTING=re.search(r'/listing/([0-9a-f-]{36})',html).group(1)
USER='11111111-1111-4111-8111-111111111111';AGENT='22222222-2222-4222-8222-222222222222';CHAT='33333333-3333-4333-8333-333333333333';PHONE='255700000000'
def setup(browser,mode,width=390,language='en'):
 context=browser.new_context(viewport={'width':width,'height':950},reduced_motion='reduce')
 context.add_cookies([{'name':'kodimali_language','value':language,'url':BASE}])
 enc=lambda x:base64.urlsafe_b64encode(json.dumps(x).encode()).decode().rstrip('=')
 user={'id':USER,'aud':'authenticated','role':'authenticated','email':'fixture@example.invalid','created_at':'2026-01-01T00:00:00Z'}
 expiry=int(time.time())+3600;token=enc({'alg':'HS256','typ':'JWT'})+'.'+enc({'sub':USER,'exp':expiry,'aud':'authenticated'})+'.fixture'
 storage={'kodimali-language':language,'kodimali_welcome_seen_v1':'fixture','kodimali_browser_device_id':'fixture','sb-tlhoajedyaeaaqtrjqqh-auth-token':json.dumps({'access_token':token,'refresh_token':'fixture','token_type':'bearer','expires_in':3600,'expires_at':expiry,'user':user})}
 context.add_init_script('Object.entries('+json.dumps(storage)+').forEach(([key,value])=>localStorage.setItem(key,value));')
 calls=[]
 def api(route):
  from urllib.parse import urlparse
  path=urlparse(route.request.url).path
  body=route.request.post_data_json if route.request.method=='POST' else None
  calls.append((path,body));data=[];status=200
  if path.endswith('/auth/v1/user'):data=user
  elif path.endswith('/chat_payments_enabled'):data=mode not in ['free','unknown']
  elif path.endswith('/paid_chat_unlock_price'):data=2700
  elif path.endswith('/get_public_listing_detail'):data=[{'agent_id':AGENT}]
  elif path.endswith('/listing_chat_access'):data=[{'agent_id':AGENT,'revoked_at':None,'expires_at':'2099-01-01T00:00:00Z'}] if mode=='existing' else []
  elif path.endswith('/create-listing-chat-payment'):
   assert mode in ['free','existing'],'Unexpected payment initiation'
   assert body['phone_number']=='' and 'expected_amount' not in body
   data={'paymentRequired':False,'paymentStatus':'free'}
  elif path.endswith('/get_or_create_listing_conversation'):data=[{'id':CHAT}]
  elif path.endswith('/api/listing-contact-payment'):
   if mode=='unknown':status=503;data={'error':'Temporary test outage'}
   elif body.get('quote_only'):data={'paymentRequired':mode=='paid','amount':1500,'currency':'TZS',**({'phoneNumber':PHONE} if mode!='paid' else {})}
   else:
    assert mode=='paid' and body.get('expected_amount')==1500
    data={'paymentId':'fixture-payment','accessToken':'fixture-capability','paymentStatus':'pending','amount':1500,'currency':'TZS'}
  elif path.endswith('/api/listing-contact-payment/status'):data={'paymentStatus':'paid','phoneNumber':PHONE,'accessExpiresAt':'2099-01-01T00:00:00Z'}
  route.fulfill(status=status,content_type='application/json',body=json.dumps(data))
 context.route('**/auth/v1/**',api);context.route('**/rest/v1/**',api);context.route('**/functions/v1/**',api);context.route('**/api/listing-contact-payment**',api)
 context.route('https://wa.me/**',lambda route:route.fulfill(status=200,content_type='text/html',body='<p>WhatsApp destination verified</p>'))
 return context,calls
with sync_playwright() as pw:
 browser=pw.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
 for width,language in [(390,"en"),(390,"sw"),(1440,"en")]:
  context,calls=setup(browser,'free',width,language);page=context.new_page();page.goto(BASE+f'/listing/{LISTING}/contact',wait_until='domcontentloaded',timeout=90000)
  expect(page.get_by_role('link',name='WhatsApp '+PHONE,exact=True)).to_have_attribute('href','https://wa.me/'+PHONE)
  expect(page.get_by_text('Pay and unlock number',exact=True)).to_have_count(0);expect(page.get_by_text('Full name',exact=True)).to_have_count(0)
  assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
  page.screenshot(path='tmp/contact-ux-free-'+language+'-'+str(width)+'.png',full_page=True);print('PASS: free contact shows linked number without payment form',width,language,flush=True);context.close()
 for mode in ['free','existing']:
  context,calls=setup(browser,mode);page=context.new_page();page.goto(BASE+f'/listing/{LISTING}/chat',wait_until='domcontentloaded',timeout=90000)
  expect(page).to_have_url(re.compile('/account/chat/'+CHAT),timeout=25000)
  assert len([p for p,b in calls if p.endswith('/create-listing-chat-payment')])==1
  print('PASS:',mode,'chat opens directly without payment details',flush=True);context.close()
 context,calls=setup(browser,'paid');page=context.new_page();page.goto(BASE+f'/listing/{LISTING}/contact?intent=whatsapp',wait_until='domcontentloaded',timeout=90000)
 page.get_by_label('Full name',exact=True).fill('Fixture Customer');page.get_by_label('Phone number',exact=True).fill(PHONE)
 page.get_by_role('button',name='Pay TZS 1,500 and continue',exact=True).click()
 expect(page).to_have_url('https://wa.me/'+PHONE,timeout=20000)
 print('PASS: paid WhatsApp intent continues to agent WhatsApp after verified confirmation',flush=True);context.close()
 context,calls=setup(browser,'paid');page=context.new_page();page.goto(BASE+f'/listing/{LISTING}/chat',wait_until='domcontentloaded',timeout=90000)
 expect(page.get_by_label('Mobile-money number',exact=True)).to_be_visible()
 expect(page.get_by_role('button',name='Pay TZS 2,700 and continue',exact=True)).to_be_visible()
 assert not any(p.endswith('/create-listing-chat-payment') for p,b in calls)
 print('PASS: paid chat displays configured price and waits for explicit action',flush=True);context.close()
 context,calls=setup(browser,'unknown');page=context.new_page();page.goto(BASE+f'/listing/{LISTING}/contact',wait_until='domcontentloaded',timeout=90000)
 expect(page.get_by_role('button',name='Try again',exact=True)).to_be_visible();expect(page.get_by_label('Full name',exact=True)).to_have_count(0)
 print('PASS: unavailable settings show retry without a guessed price or payment form',flush=True);context.close();browser.close()
