"""Read-only deployment smoke test. Advertising metrics are intercepted."""
import json,re,xml.etree.ElementTree as ET
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
with sync_playwright() as pw:
 browser=pw.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
 results=[]
 for width in [390,1440]:
  ctx=browser.new_context(viewport={'width':width,'height':900});ctx.add_cookies([{'name':'kodimali_language','value':'en','url':'https://kodimali.com'}])
  ctx.add_init_script("localStorage.setItem('kodimali_browser_device_id','audit');localStorage.setItem('kodimali_welcome_seen_v1','audit');localStorage.setItem('kodimali-language','en');Object.defineProperty(window,'sessionStorage',{get(){throw new Error('blocked')}})")
  ctx.route('**/rest/v1/rpc/record_platform_promotion_event',lambda route:route.fulfill(status=200,content_type='application/json',body='null'))
  page=ctx.new_page();errors=[];page.on('pageerror',lambda error:errors.append(str(error)))
  response=page.goto('https://kodimali.com/listings');assert response.status==200
  expect(page.locator('.listing-location-trigger')).to_be_visible();assert not page.evaluate('document.documentElement.scrollWidth>innerWidth')
  page.locator('.listing-location-trigger').click();dialog=page.locator('dialog[open]');expect(dialog).to_be_visible()
  expect(dialog.get_by_label('Ward',exact=True)).to_be_visible();expect(dialog.get_by_label('Area',exact=True)).to_be_visible()
  assert dialog.get_by_role('button',name='Show results',exact=True).evaluate('(el)=>getComputedStyle(el).color')=='rgb(255, 255, 255)'
  box=dialog.bounding_box();assert box['x']>=0 and box['x']+box['width']<=width+1
  page.screenshot(path=f'design-previews/listing-location-ads/live-location-{width}.png')
  page.keyboard.press('Escape');expect(dialog).to_have_count(0)
  ads=page.locator('.kodimali-promotion-card');heights=[]
  if ads.count():
   assert ads.count()==1;ads.first.scroll_into_view_if_needed();page.wait_for_timeout(1500)
   height=ads.first.bounding_box()['height'];assert height<550,height;heights.append(height)
   expect(ads.first.get_by_role('link',name='Browse listings')).to_have_attribute('href','/listings')
   page.screenshot(path=f'design-previews/listing-location-ads/live-ads-{width}.png')
   more=page.get_by_role('button',name=re.compile('More sponsored ads'))
   if more.count():more.click();assert ads.count()>1
  assert not errors,errors
  results.append({'width':width,'ad_heights':heights,'errors':errors})
  ctx.close()
 ctx=browser.new_context();page=ctx.new_page();response=page.goto('https://kodimali.com/sitemap.xml');assert response.status==200
 xml=response.text();root=ET.fromstring(xml);assert root.tag.endswith('urlset')
 assert '/events<' in xml and '/toa-taarifa<' in xml
 assert not any('/'+path+'<' in xml for path in ['account','manage','admin','login'])
 results.append({'sitemap_status':200,'format':'urlset'})
 Path('tmp/listing-ads-live-results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
 browser.close();print('PASS live mobile/desktop dialogs, ads, blocked storage, readable buttons and sitemap')
