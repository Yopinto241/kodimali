"""Read-only bilingual browser checks. Authenticated screens use intercepted fixture sessions, never real accounts."""
import base64,json,os,time
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('LANG_TEST_BASE','http://127.0.0.1:3101');OUT=Path('tmp/language-checks');OUT.mkdir(parents=True,exist_ok=True)
USER='11111111-1111-4111-8111-111111111111';OWNER='22222222-2222-4222-8222-222222222222';CATEGORY='33333333-3333-4333-8333-333333333333'
def switch(page,language):
 page.locator('select.nav-control:visible').first.select_option(language)
 expect(page.locator('html')).to_have_attribute('lang',language)
 page.wait_for_timeout(100)
def seed(context,role=None):
 storage={'kodimali-language':'sw','kodimali_browser_device_id':'language-test','kodimali_welcome_seen_v1':'language-test'}
 if role:
  user={'id':USER,'aud':'authenticated','role':'authenticated','email':'translation-fixture@example.invalid','created_at':'2026-01-01T00:00:00Z'}
  enc=lambda x:base64.urlsafe_b64encode(json.dumps(x).encode()).decode().rstrip('=')
  expiry=int(time.time())+3600;token=enc({'alg':'HS256','typ':'JWT'})+'.'+enc({'sub':USER,'exp':expiry,'aud':'authenticated'})+'.fixture'
  storage['sb-tlhoajedyaeaaqtrjqqh-auth-token']=json.dumps({'access_token':token,'refresh_token':'fixture','token_type':'bearer','expires_in':3600,'expires_at':expiry,'user':user})
  context.route('**/auth/v1/user',lambda r:r.fulfill(status=200,content_type='application/json',body=json.dumps(user)))
  def api(route):
   path=urlparse(route.request.url).path;data=[]
   if path.endswith('/user_roles'):data=[{'role':role}]
   elif path.endswith('/get_my_admin_permissions'):data=['*']
   elif path.endswith('/get_manage_dashboard_counts'):data={'listings':0,'requests':0,'agents':0}
   elif path.endswith('/owner_profiles'):data={'id':OWNER,'profile_id':USER,'full_name':'Amina apartment book booking','verification_status':'verified','account_status':'active'} if role=='owner' else None
   elif path.endswith('/agents'):data={'id':OWNER,'profile_id':USER,'verification_status':'approved','account_status':'active'} if role=='agent' else []
   elif path.endswith('/agent_service_categories'):data=[{'asset_categories':{'id':CATEGORY,'name':'House','slug':'house','field_schema':[{'key':'bedrooms','label':'Bedrooms','type':'number','required':True},{'key':'land_size_unit','label':'Land size unit','type':'select','options':['acre','hectare','sqm']}]}}]
   elif path.endswith('/profiles'):data={'id':USER,'full_name':'Amina apartment book booking','preferred_language':'sw'}
   elif path.endswith('/get_business_dashboard'):data={}
   route.fulfill(status=200,content_type='application/json',body=json.dumps(data))
  context.route('**/rest/v1/**',api)
 context.add_init_script('Object.entries('+json.dumps(storage)+').forEach(([key,value])=>{if(localStorage.getItem(key)===null)localStorage.setItem(key,value)});')
with sync_playwright() as pw:
 browser=pw.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
 for width in [390,1440]:
  context=browser.new_context(viewport={'width':width,'height':900},reduced_motion='reduce');seed(context);page=context.new_page();errors=[];page.on('pageerror',lambda error:errors.append(str(error)))
  cases=[('/login','Ingia KODIMALI','Sign in to KODIMALI'),('/register','Fungua akaunti ya KODIMALI','Create a KODIMALI account'),('/privacy','Taarifa zako zinapaswa kuwa na matumizi yaliyo wazi.','Your information should have a clear purpose.'),('/safety','Kagua kwanza. Thibitisha wakala. Linda kila malipo.','Inspect first. Verify the agent. Protect every payment.'),('/manage','Mlango mmoja salama wa shughuli za biashara.','One secure entrance for the business side.'),('/events','Vifaa na wataalamu wa matukio','Event equipment and professionals')]
  for path,sw,en in cases:
   page.goto(BASE+path);switch(page,'sw');expect(page.get_by_text(sw,exact=True).first).to_be_visible();switch(page,'en');expect(page.get_by_text(en,exact=True).first).to_be_visible();switch(page,'sw');expect(page.get_by_text(sw,exact=True).first).to_be_visible()
   assert not page.evaluate('document.documentElement.scrollWidth>innerWidth'),(width,path)
  page.goto(BASE+'/listings');search=page.locator('input[name="q"]').first;search.fill('Amina apartment book booking');switch(page,'en');expect(search).to_have_value('Amina apartment book booking');switch(page,'sw');expect(search).to_have_value('Amina apartment book booking')
  page.goto(BASE+'/category/apartment');switch(page,'sw');expect(page.locator('main h1')).to_have_text('Apartment');switch(page,'en');expect(page.locator('main h1')).to_have_text('Apartment')
  page.goto(BASE+'/privacy');switch(page,'en');page.reload();expect(page.locator('html')).to_have_attribute('lang','en');expect(page.get_by_role('heading',name='Your information should have a clear purpose.',exact=True)).to_be_visible()
  page.screenshot(path=str(OUT/f'privacy-en-{width}.png'),full_page=True)
  assert not errors,errors;context.close();print(f'PASS {width}px: public screens switch both ways, typed data/Apartment unchanged, persistence and no overflow',flush=True)
 for role,path,sw,en in [('customer','/account?section=bookings','Miadi na Booking Zangu','My Appointments and Booking'),('admin','/manage','Muhtasari','Dashboard'),('agent','/agent','Muhtasari wa sasa','Live overview'),('owner','/owner','Biashara yako ya kukodisha','Your rental business')]:
  context=browser.new_context(viewport={'width':1440,'height':900},reduced_motion='reduce');seed(context,role);page=context.new_page();page.goto(BASE+path);switch(page,'sw');expect(page.get_by_text(sw,exact=True).first).to_be_visible();switch(page,'en');expect(page.get_by_text(en,exact=True).first).to_be_visible();switch(page,'sw');expect(page.get_by_text(sw,exact=True).first).to_be_visible();page.screenshot(path=str(OUT/f'{role}-sw.png'),full_page=True)
  if role=='agent':
   switch(page,'en');page.get_by_role('link',name='Add asset',exact=True).click();page.locator('main form select').first.select_option(CATEGORY);page.get_by_label('Bedrooms',exact=False).fill('3');page.locator('main select').last.select_option('acre');switch(page,'sw');expect(page.get_by_label('Vyumba vya kulala',exact=False)).to_have_value('3');expect(page.locator('main select').last).to_have_value('acre');expect(page.get_by_role('option',name='ekari',exact=True)).to_have_count(1);switch(page,'en');expect(page.locator('main select').last).to_have_value('acre');print('PASS agent configured fields translate without changing numbers or stored option values',flush=True)
  context.close();print('PASS',role,'workspace switches both ways with fixture authentication',flush=True)
 browser.close()
