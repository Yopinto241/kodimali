"""Acceptance checks for the confirmed public location/price filter repairs."""
import os,json
from urllib.parse import urlparse,parse_qs
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('FILTER_REPAIR_BASE','http://127.0.0.1:3101')
expect.set_options(timeout=15000)
with sync_playwright() as pw:
 browser=pw.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
 for width,lang in [(390,'en'),(1440,'en'),(390,'sw')]:
  sw=lang=='sw';ctx=browser.new_context(viewport={'width':width,'height':1000})
  ctx.add_cookies([{'name':'kodimali_language','value':lang,'url':BASE}]);ctx.add_init_script("localStorage.setItem('kodimali_browser_device_id','audit');localStorage.setItem('kodimali_welcome_seen_v1','audit');localStorage.setItem('kodimali-language','"+lang+"')")
  ctx.route('**/rest/v1/rpc/record_platform_promotion_event',lambda r:r.fulfill(status=200,content_type='application/json',body='null'))
  held=[];stall=[width==390 and not sw]
  def lookup(route):
   if stall[0]:held.append(route);return
   kind=parse_qs(urlparse(route.request.url).query)['locationType'][0]
   rows=[] if kind=='area' else [{'id':'70000000-0000-4000-8000-'+('2' if kind=='district' else '3').zfill(12),'name':'Fixture '+kind}]
   route.fulfill(status=200,content_type='application/json',body=json.dumps(rows))
  ctx.route('**/api/locations?*',lookup)
  page=ctx.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)));page.goto(BASE+'/listings?category=house')
  page.locator('.listing-location-filter > .listing-location-trigger').click();dialog=page.locator('dialog[open]');show=dialog.locator('.btn-success');expect(show).to_be_enabled();dialog.locator('select').first.select_option(index=1)
  if stall[0]:
   expect(dialog.get_by_role('alert')).to_be_visible(timeout=16000);expect(show).to_be_enabled();expect(dialog.get_by_role('button',name='Retry',exact=True)).to_be_visible();stall[0]=False
   for route in held:
    try:route.abort('timedout')
    except Exception:pass
   dialog.get_by_role('button',name='Retry',exact=True).click()
   print('PASS stalled lookup stops after 10 seconds; retry and parent-only search available',flush=True)
  expect(dialog.locator('select').nth(1)).to_be_enabled();dialog.locator('select').nth(1).select_option(index=1);expect(dialog.locator('select').nth(2)).to_be_enabled();dialog.locator('select').nth(2).select_option(index=1)
  expect(dialog.get_by_text('Hakuna maeneo yaliyohifadhiwa hapa. Unaweza kutafuta kwa kata uliyochagua.' if sw else 'No areas are saved here. You can search using the selected ward.',exact=True)).to_be_visible();expect(dialog.locator('select').nth(3)).to_be_disabled();expect(show).to_be_enabled();page.keyboard.press('Escape')
  panel=page.locator('.search-price-filter');panel.locator('summary').click();minimum=page.locator('input[name=minPrice]');maximum=page.locator('input[name=maxPrice]');minimum.fill('-1');panel.locator('summary').click();page.locator('select[name=category]').select_option('other-asset')
  expect(page.locator('form#filters [role=alert]')).to_contain_text('Weka bei sahihi' if sw else 'Enter a valid price');expect(panel).to_have_attribute('open','');expect(minimum).to_be_focused();expect(page.locator('select[name=category]')).to_have_value('house');assert page.url==BASE+'/listings?category=house'
  minimum.fill('10000');maximum.fill('100');panel.locator('button').click();expect(page.locator('form#filters [role=alert]')).to_contain_text('Bei ya juu' if sw else 'Maximum price');expect(maximum).to_be_focused();assert page.url==BASE+'/listings?category=house'
  minimum.fill('100');maximum.fill('10000');page.locator('select[name=pricePeriod]').select_option('month');page.locator('select[name=category]').select_option('other-asset');page.wait_for_url('**/listings?*category=other-asset*',timeout=30000)
  query=parse_qs(urlparse(page.url).query);assert query['minPrice']==['100'] and query['maxPrice']==['10000'] and query['pricePeriod']==['month'];expect(page.locator('select[name=category]')).to_have_value('other-asset');assert not errors,errors
  print('PASS empty-area guidance, hidden-price recovery, reversed-range validation and valid combined navigation',width,lang,flush=True)
  page.goto(BASE+'/category/house');page.locator('.search-price-filter summary').click();page.locator('input[name=minPrice]').fill('10000');page.locator('input[name=maxPrice]').fill('100');page.locator('.search-price-popover button').click();expect(page.locator('form#filters [role=alert]')).to_be_visible();assert page.url==BASE+'/category/house'
  page.locator('input[name=minPrice]').fill('100');page.locator('input[name=maxPrice]').fill('10000');page.locator('.search-price-popover button').click();page.wait_for_url('**/category/house?*minPrice=100*maxPrice=10000*',timeout=30000);assert not errors,errors
  print('PASS category page shares price validation and keeps its category route',width,lang,flush=True)
  ctx.close()
 browser.close()
