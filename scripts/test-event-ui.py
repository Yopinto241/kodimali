"""Browser regression checks using intercepted public catalog fixtures; never writes to Supabase."""
import base64, json, os, sys, time
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright, expect
BASE=os.environ.get('EVENT_UI_BASE','http://localhost:3000')
OUT=Path('tmp/event-ui-checks');OUT.mkdir(parents=True,exist_ok=True)
E='11111111-1111-4111-8111-111111111111';T='22222222-2222-4222-8222-222222222222';R='33333333-3333-4333-8333-333333333333';D='44444444-4444-4444-8444-444444444444';C='55555555-5555-4555-8555-555555555555'
item={'id':E,'name':'White wedding chairs with comfortable padded seats','category_id':C,'category_name_en':'Chairs','category_name_sw':'Viti','price_amount_tzs':1000,'price_unit':'item_day','total_quantity':100,'available_quantity':100,'media_paths':[],'public_location_label':'Dar es Salaam'}
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
 for width in [320,390,1440]:
  context=browser.new_context(viewport={'width':width,'height':900},reduced_motion='reduce')
  context.add_init_script("localStorage.setItem('kodimali-language','en');localStorage.setItem('kodimali_browser_device_id','ui-test');localStorage.setItem('kodimali_welcome_seen_v1','ui-test');")
  calls=[];available=[True]
  def api(route):
   path=urlparse(route.request.url).path;body=route.request.post_data_json if route.request.method=='POST' else None;calls.append((path,body))
   data=[]
   if path.endswith('/event_types'):data=[{'id':T,'name_en':'Wedding','name_sw':'Harusi'}]
   elif path.endswith('/event_equipment_categories'):data=[{'id':C,'name_en':'Chairs','name_sw':'Viti'}]
   elif path.endswith('/locations'):
    url=route.request.url
    if 'location_type=eq.country' in url:data={'id':'66666666-6666-4666-8666-666666666666'}
    else:
     location={'id':D,'name':'Ilala','location_type':'district','parent_id':R} if D in url else {'id':R,'name':'Dar es Salaam','location_type':'region','parent_id':None}
     data=location
   elif path.endswith('/search_public_event_equipment'):data=[item]
   elif path.endswith('/search_public_event_services'):data=[]
   elif path.endswith('/submit_event_plan'):data={'reference':'EVT-UI-TEST'}
   elif path.endswith('/check_public_event_selection'):data=[{'kind':x['kind'],'id':x['id'],'is_available':available[0],'available_quantity':100} for x in body['p_items']]
   route.fulfill(status=200,content_type='application/json',body=json.dumps(data))
  context.route('**/rest/v1/**',api)
  def locations(route):
   q=route.request.url
   data=[{'id':R,'name':'Dar es Salaam'}] if 'locationType=region' in q else [{'id':D,'name':'Ilala'}] if 'locationType=district' in q else []
   route.fulfill(status=200,content_type='application/json',body=json.dumps(data))
  context.route('**/api/locations?*',locations)
  page=context.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.goto(BASE+'/events/plan');expect(page.get_by_role('button',name='Continue',exact=True).first).to_be_enabled()
  page.get_by_role('button',name='Continue',exact=True).first.click();expect(page.get_by_text('Choose an event type.',exact=True)).to_be_visible()
  page.get_by_label('Event name (optional)').fill('Family wedding');page.locator('main select').first.select_option(T)
  page.locator('input[type=datetime-local]').nth(0).fill('2027-02-15T10:00');page.locator('input[type=datetime-local]').nth(1).fill('2027-02-15T18:00')
  page.screenshot(path=str(OUT/f'details-{width}.png'),full_page=True)
  page.get_by_role('combobox',name='Region',exact=True).select_option(R);page.get_by_label('District',exact=True).select_option(D)
  page.get_by_role('button',name='Continue',exact=True).first.click();expect(page.get_by_text(item['name'],exact=True).first).to_be_visible()
  page.get_by_role('checkbox').check();page.get_by_label('Quantity',exact=True).fill('25')
  page.get_by_role('button',name='1. Event details').click();page.get_by_role('combobox',name='Region',exact=True).select_option('');page.get_by_role('combobox',name='Region',exact=True).select_option(R)
  page.get_by_role('button',name='Continue',exact=True).first.click();expect(page.get_by_role('checkbox')).to_be_checked();expect(page.get_by_label('Quantity',exact=True)).to_have_value('25')
  page.reload();expect(page.get_by_label('Event name (optional)')).to_have_value('Family wedding')
  page.get_by_role('button',name='2. Equipment & services').click();expect(page.get_by_role('checkbox')).to_be_checked()
  available[0]=False;page.get_by_role('button',name='Continue',exact=True).first.click();expect(page.get_by_role('button',name='Request event quotation',exact=True)).to_be_disabled()
  available[0]=True;page.get_by_role('button',name='Recheck availability',exact=True).click();expect(page.get_by_role('button',name='Request event quotation',exact=True)).to_be_enabled()
  assert not page.evaluate('document.documentElement.scrollWidth > innerWidth'),f'Overflow at {width}'
  assert page.locator('main h2').first.evaluate('(e)=>getComputedStyle(e).color')=='rgb(36, 55, 47)'
  assert page.locator('.mobile-bottom-nav').count()==0
  page.screenshot(path=str(OUT/f'plan-review-{width}.png'),full_page=True)
  page.get_by_role('button',name='Request event quotation',exact=True).click();page.wait_for_url('**/login?next=/events/plan')
  assert json.loads(page.evaluate('localStorage.getItem("kodimali-event-draft-v2")'))['draft']['choices'][0]['quantity']==25
  page.goto(BASE+'/events');expect(page.get_by_role('heading',name='Event equipment and professionals')).to_be_visible()
  page.get_by_label('Search equipment or services').fill('chairs');page.wait_for_timeout(600)
  assert any(path.endswith('search_public_event_equipment') and body and body.get('p_search')=='chairs' and body.get('p_min_price') is None for path,body in calls)
  page.get_by_role('button',name='Professionals',exact=True).click();page.get_by_label('Service category',exact=True).select_option('photographer');page.wait_for_timeout(300)
  assert any(path.endswith('search_public_event_services') and body and body.get('p_provider_kind')=='photographer' for path,body in calls)
  assert not page.evaluate('document.documentElement.scrollWidth > innerWidth')
  page.screenshot(path=str(OUT/f'events-{width}.png'),full_page=True)
  assert not errors,errors
  print(f'PASS {width}px: validation, selection persistence, location edits, reload, availability hold, login recovery, independent filters, readable headings and no overflow')
  if width==1440:
   user={'id':E,'aud':'authenticated','role':'authenticated','email':'ui-fixture@example.invalid','created_at':'2026-01-01T00:00:00Z'}
   context.route('**/auth/v1/user',lambda route:route.fulfill(status=200,content_type='application/json',body=json.dumps(user)))
   def encoded(value):return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip('=')
   expiry=int(time.time())+3600;token=encoded({'alg':'HS256','typ':'JWT'})+'.'+encoded({'sub':E,'exp':expiry,'aud':'authenticated'})+'.fixture'
   session={'access_token':token,'refresh_token':'fixture','token_type':'bearer','expires_in':3600,'expires_at':expiry,'user':user}
   page.evaluate('(session)=>localStorage.setItem("sb-tlhoajedyaeaaqtrjqqh-auth-token",JSON.stringify(session))',session)
   page.goto(BASE+'/events/plan');page.get_by_role('button',name='3. Review & send').click()
   expect(page.get_by_role('button',name='Request event quotation',exact=True)).to_be_enabled();page.get_by_role('button',name='Request event quotation',exact=True).click()
   expect(page.get_by_role('heading',name='Your quotation request has been sent')).to_be_visible()
   expect(page.get_by_text('EVT-UI-TEST',exact=True)).to_be_visible()
   assert page.evaluate('localStorage.getItem("kodimali-event-draft-v2")') is None
   submitted=[body for path,body in calls if path.endswith('/submit_event_plan')]
   assert len(submitted)==1 and submitted[0]['p_items'][0]['quantity']==25 and submitted[0]['p_idempotency_key']
   print('PASS signed-in success, exact submitted quantity, idempotency key and draft cleanup (mocked API, no live writes)')
  context.close()
 browser.close()
