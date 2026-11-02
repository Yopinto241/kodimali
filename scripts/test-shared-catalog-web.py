"""Shared category/global filters and ward-wide GPS, with isolated browser GPS/RPC fixtures."""
import os,json
from pathlib import Path
from urllib.parse import urlparse,parse_qs
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('CATALOG_TEST_BASE','http://127.0.0.1:3101');OUT=Path('design-previews/shared-catalog');OUT.mkdir(parents=True,exist_ok=True)
expect.set_options(timeout=20000)
def uid(n):return '70000000-0000-4000-8000-'+str(n).zfill(12)
with sync_playwright() as pw:
 browser=pw.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
 # A slow script download cannot accept and lose a filter click before hydration.
 gate=browser.new_context(viewport={'width':390,'height':1000});held_scripts=[];block=[True]
 def scripts(route):
  if block[0] and route.request.resource_type=='script':held_scripts.append(route)
  else:route.continue_()
 gate.add_init_script("localStorage.setItem('kodimali_welcome_seen_v1','audit');localStorage.setItem('kodimali_browser_device_id','audit')")
 gate.route('**/_next/static/**',scripts)
 warm=gate.new_page();warm.goto(BASE+'/category/house',wait_until='commit');manual=warm.locator('.listing-location-filter > button');expect(manual).to_be_disabled();block[0]=False
 for route in list(held_scripts):route.continue_()
 expect(manual).to_be_enabled(timeout=30000);manual.click();expect(warm.locator('dialog[open]')).to_be_visible();gate.close();print('PASS slow script loading keeps controls disabled until interactive; first click opens location',flush=True)
 for width,language in [(390,'en'),(1440,'sw')]:
  sw=language=='sw';ctx=browser.new_context(viewport={'width':width,'height':1000},permissions=['geolocation'],geolocation={'latitude':-6.8,'longitude':39.2})
  ctx.add_cookies([{'name':'kodimali_language','value':language,'url':BASE}]);ctx.add_init_script("localStorage.setItem('kodimali_browser_device_id','audit');localStorage.setItem('kodimali_welcome_seen_v1','audit');localStorage.setItem('kodimali-language','"+language+"')")
  ctx.route('**/rest/v1/rpc/record_platform_promotion_event',lambda r:r.fulfill(status=200,content_type='application/json',body='null'))
  page=ctx.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)));page.goto(BASE+'/listings');expect(page.locator('#filters')).to_be_visible();categories=page.locator('select[name=category] option').evaluate_all('(nodes)=>nodes.map(n=>n.value).filter(value=>value&&value!=="events")')
  for slug in categories:
   page.goto(BASE+'/category/'+slug);form=page.locator('form#filters');expect(form).to_be_visible();assert 'search-results-head' in form.get_attribute('class')
   expect(page.locator('select[name=category],.category-route-picker')).to_have_count(0)
   expect(form.locator('.listing-location-filter > button')).to_be_visible();expect(form.get_by_role('button',name='Tumia eneo nilipo' if sw else 'Use my location',exact=True)).to_be_visible();expect(form.locator('select[name=sort]')).to_be_visible();expect(form.get_by_role('button',name='Ondoa vichujio' if sw else 'Clear filters',exact=True)).to_be_visible()
   expect(page.get_by_role('button',name='Hifadhi utafutaji' if sw else 'Save this search',exact=True)).to_be_visible()
   assert form.get_attribute('action')=='/category/'+slug
  print('PASS shared global filter layout, GPS/manual/price/sort/clear/save, no category selector, all categories',len(categories),width,language,flush=True)
  page.goto(BASE+'/category/house');form=page.locator('form#filters');form.locator('.search-price-filter summary').click();form.locator('input[name=minPrice]').fill('100');form.locator('input[name=maxPrice]').fill('1000000');form.locator('select[name=pricePeriod]').select_option('month');form.locator('input[name=q]').fill('fixture');form.locator('.search-price-popover button').click();page.wait_for_url('**/category/house?*minPrice=100*maxPrice=1000000*',timeout=30000)
  # Fixture locations are valid UUIDs; all location and resolver responses are scoped to this context.
  def locations(route):
   kind=parse_qs(urlparse(route.request.url).query)['locationType'][0];n={'district':2,'ward':3,'area':4}[kind];route.fulfill(status=200,content_type='application/json',body=json.dumps([{'id':uid(n),'name':'Fixture '+kind}]))
  ctx.route('**/api/locations?*',locations)
  page.locator('.listing-location-filter > button').click();dialog=page.locator('dialog[open]');expect(dialog.locator('.btn-success')).to_be_enabled();region=dialog.locator('select').first.locator('option').nth(1).get_attribute('value')
  for index in range(4):
   field=dialog.locator('select').nth(index);expect(field).to_be_enabled();expect(field.locator('option')).not_to_have_count(1);field.select_option(index=1)
  dialog.locator('.btn-success').click();page.wait_for_url('**/category/house?*areaId=*',timeout=30000);query=parse_qs(urlparse(page.url).query);assert query['areaId']==[uid(4)] and query['minPrice']==['100'];assert 'category' not in query
  # Sort auto-applies just as on global listings and retains all independent filters.
  page.locator('select[name=sort]').select_option('price_low');page.wait_for_url('**/category/house?*sort=price_low*',timeout=30000)
  gps_calls=[];outcome=['success'];held=[]
  def resolver(route):
   gps_calls.append(route.request.post_data_json)
   if outcome[0]=='hang':held.append(route);return
   data=[] if outcome[0]=='empty' else [{'region_id':region,'district_id':uid(2),'ward_id':uid(3),'ward_name':'Fixture ward','area_id':uid(4)}]
   route.fulfill(status=200,content_type='application/json',body=json.dumps(data))
  ctx.route('**/rest/v1/rpc/resolve_location_hierarchy',resolver)
  page.get_by_role('button',name='Tumia eneo nilipo' if sw else 'Use my location',exact=True).click();gps=page.locator('dialog[open]');confirm=gps.get_by_role('button',name='Tafuta katika kata hii' if sw else 'Search this ward',exact=True);expect(confirm).to_be_visible()
  page.screenshot(path=str(OUT/f'gps-{width}-{language}.png'));confirm.click();page.wait_for_url('**/category/house?*wardId=*',timeout=30000);expect(page.locator('input[name=areaId]')).to_have_count(0)
  query=parse_qs(urlparse(page.url).query);assert query['wardId']==[uid(3)] and query['minPrice']==['100'] and query['sort']==['price_low'];assert not any(k in query for k in ['lat','lng','areaId','category']);assert gps_calls[0]['p_latitude']==-6.8
  assert page.evaluate("localStorage.getItem('customer_area_id')===null&&localStorage.getItem('customer_latitude')===null&&localStorage.getItem('customer_longitude')===null")
  print('PASS manual area selection, GPS widens to ward only, combined filters and sort stay on category',width,language,flush=True)
  page.get_by_role('button',name='Ondoa vichujio' if sw else 'Clear filters',exact=True).click();page.wait_for_url(BASE+'/category/house');expect(page.locator('input[name=q]')).to_have_value('');expect(page.locator('input[name=minPrice]')).to_have_value('');expect(page.locator('select[name=sort]')).to_have_value('recommended');assert page.evaluate("['region_id','district_id','ward_id','area_id','latitude','longitude'].every(k=>localStorage.getItem('customer_'+k)===null)")
  page.locator('input[name=q]').fill('unsaved draft');page.get_by_role('button',name='Ondoa vichujio' if sw else 'Clear filters',exact=True).click();expect(page.locator('input[name=q]')).to_have_value('')
  # An unresolved ward keeps manual selection available and does not navigate.
  outcome[0]='empty';before=page.url;page.get_by_role('button',name='Tumia eneo nilipo' if sw else 'Use my location',exact=True).click();gps=page.locator('dialog[open]');expect(gps.get_by_role('alert')).to_be_visible();assert page.url==before;gps.get_by_role('button',name='Chagua mwenyewe' if sw else 'Choose manually',exact=True).click();expect(page.locator('dialog[open]').get_by_role('heading',name='Chagua eneo' if sw else 'Choose location',exact=True)).to_be_visible();page.keyboard.press('Escape')
  if not sw:
   # Denial is delivered by the browser callback; manual browsing remains usable.
   page.evaluate("() => { navigator.geolocation.getCurrentPosition=(ok,fail)=>fail({code:1,message:'fixture denied'}); }");outcome[0]='success';page.get_by_role('button',name='Use my location',exact=True).click();expect(page.locator('dialog[open]').get_by_role('alert')).to_be_visible();page.keyboard.press('Escape')
  assert not errors,errors;assert not page.evaluate('document.documentElement.scrollWidth>innerWidth');page.screenshot(path=str(OUT/f'category-{width}-{language}.png'));print('PASS clear filters including unsaved values/preferences, GPS failure/manual recovery, responsive layout',width,language,flush=True);ctx.close()
 browser.close()
