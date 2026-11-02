import json,os
from urllib.parse import urlparse,parse_qs
from playwright.sync_api import sync_playwright,expect
base=os.environ.get('REGISTRATION_UI_BASE','http://127.0.0.1:3101')
def uid(n):return '70000000-0000-4000-8000-'+str(n).zfill(12)
locations=[{'id':uid(n),'parent_id':uid(n-1) if n>1 else None,'name':name,'location_type':kind} for n,name,kind in [(1,'Tanzania','country'),(2,'Arusha','region'),(3,'Arusha District','district'),(4,'Sokoni','ward'),(5,'Central','area')]]
typed=os.environ.get('TYPED_AREA')=='1'
if typed:locations=[r for r in locations if r['location_type']!='area']
with sync_playwright() as pw:
 browser=pw.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
 for width,language in [(390,'en'),(390,'sw'),(1440,'en')]:
  ctx=browser.new_context(viewport={'width':width,'height':900})
  ctx.add_cookies([{'name':'kodimali_language','value':language,'url':base}])
  ctx.add_init_script("localStorage.setItem('kodimali_browser_device_id','audit');localStorage.setItem('kodimali_welcome_seen_v1','audit');localStorage.setItem('kodimali-language',"+json.dumps(language)+")")
  def location_api(route):
   query=parse_qs(urlparse(route.request.url).query)
   parent=query.get('parent_id',[''])[0].removeprefix('eq.')
   rows=[r for r in locations if (r['parent_id']==parent if parent else r['location_type']=='country')]
   route.fulfill(status=200,content_type='application/json',body=json.dumps(rows))
  ctx.route('**/rest/v1/locations?*',location_api)
  def save_area(route):
   body=route.request.post_data_json
   assert body['p_ward_id']==uid(4)
   name=' '.join(body['p_area_name'].split())
   row=next((r for r in locations if r['parent_id']==uid(4) and r['name'].lower()==name.lower()),None)
   created=row is None
   if created:
    row={'id':uid(5),'parent_id':uid(4),'location_type':'area','name':name};locations.append(row)
   route.fulfill(status=200,content_type='application/json',body=json.dumps([{**row,'created_new':created}]))
  ctx.route('**/rest/v1/rpc/ensure_ward_area',save_area)
  submissions=[];outcome=['server'];stalled=[]
  def signup(route):
   data=route.request.post_data_json;submissions.append(data)
   if outcome[0]=='hang':stalled.append(route);return
   elif outcome[0]=='server':route.fulfill(status=500,content_type='application/json',body='{"code":"unexpected_failure","msg":"Database error saving new user: SQLSTATE 23514 secret_constraint"}')
   elif outcome[0]=='duplicate':route.fulfill(status=422,content_type='application/json',body='{"code":"user_already_exists","msg":"User already registered"}')
   else:route.fulfill(status=200,content_type='application/json',body=json.dumps({'id':uid(99),'aud':'authenticated','role':'authenticated','email':'fixture@example.invalid','created_at':'2026-11-01T00:00:00Z','identities':[{'id':uid(99),'provider':'email'}]}))
  ctx.route('**/auth/v1/signup*',signup)
  page=ctx.new_page();errors=[];page.on('pageerror',lambda error:errors.append(str(error)))
  page.goto(base+'/manage/register/agent')
  button=page.locator('form button[type=submit],form button:not([type])').last
  # The submit button has no explicit type; location breadcrumb buttons do.
  button=page.locator('form > button')
  expect(button).to_be_disabled()
  for n in range(1,5 if typed else 6):
   picker=page.locator('select').filter(has=page.locator(f'option[value="{uid(n)}"]'))
   expect(picker).to_have_count(1);picker.select_option(uid(n))
   if n<5:expect(button).to_be_disabled()
  if typed:page.locator('input[maxlength="100"]').fill('  Central   ' if language=='en' else 'central')
  expect(button).to_be_enabled()
  for name,value in [('fullName','Fixture Agent'),('username','fixture_agent'),('email','fixture@example.invalid'),('phone','255700111222'),('nida','TEST-NIDA'),('businessName','Fixture Agency'),('password','test-password'),('confirmPassword','test-password')]:page.locator(f'input[name="{name}"]').fill(value)
  category=page.locator('select[name=categoryId]');category.select_option(index=1)
  button.click();status=page.locator('form [role=status]')
  expect(status).to_contain_text('Sorry,' if language=='en' else 'Samahani,',timeout=30000)
  assert not any(word in status.inner_text() for word in ['SQLSTATE','secret_constraint','Database','Server Error'])
  assert submissions[-1]['data']['location_id']==uid(5)
  assert submissions[-1]['data']['register_as_agent'] is True
  expect(button).to_be_enabled()
  if typed:
   page.clock.install();outcome[0]='hang'
   with page.expect_request('**/auth/v1/signup*'):button.click()
   page.clock.fast_forward(21000)
   expect(status).to_contain_text('could not confirm' if language=='en' else 'hatukuweza kuthibitisha',timeout=10000)
   expect(button).to_be_enabled()
   for route in stalled:route.abort('timedout')
  outcome[0]='duplicate';button.click();expect(status).to_contain_text('An account may already exist' if language=='en' else 'Huenda akaunti',timeout=30000)
  outcome[0]='success';button.click();expect(page.locator('h1').last).to_contain_text('Agent registration submitted' if language=='en' else 'Usajili',timeout=30000)
  assert not errors,errors
  assert not page.evaluate('document.documentElement.scrollWidth>innerWidth')
  print('PASS complete area required, exact signup payload, polite server/duplicate errors and success',width,language,flush=True)
  ctx.close()
 if typed:
  assert len([r for r in locations if r['location_type']=='area'])==1
  print('PASS typed area saved once and reused by subsequent English/Swahili applicants; stalled signup recovers',flush=True)
 browser.close()
