"""Read-only checks of the deployed inventory and autoplay. Metrics are intercepted."""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
ROOT='https://kodimali.com'
KEY='sb_publishable_3Txem_vMHZbvLswFzjR6ng_OGXbur1K'
results=[]
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
 for width in [390,1440]:
  ctx=browser.new_context(viewport={'width':width,'height':900});ctx.add_cookies([{'name':'kodimali_language','value':'en','url':ROOT}]);ctx.add_init_script("localStorage.setItem('kodimali_browser_device_id','audit');localStorage.setItem('kodimali_welcome_seen_v1','audit');localStorage.setItem('kodimali-language','en');Object.defineProperty(window,'sessionStorage',{get(){throw new Error('blocked storage')}})")
  ctx.route('**/rest/v1/rpc/record_platform_promotion_event',lambda route:route.fulfill(status=200,content_type='application/json',body='null'))
  page=ctx.new_page();errors=[];page.on('pageerror',lambda error:errors.append(str(error)))
  for path,placement,slug in [('/listings','website',None),('/category/house','category_page','house'),('/events','category_page','events')]:
   response=ctx.request.post('https://tlhoajedyaeaaqtrjqqh.supabase.co/rest/v1/rpc/get_public_sponsored_promotions',headers={'apikey':KEY,'Authorization':'Bearer '+KEY},data={'p_surface':'website','p_placement':placement,'p_category_slug':slug,'p_limit':100,'p_offset':0});assert response.ok
   expected=len(response.json());page.goto(ROOT+path);expect(page.locator('.sponsored-listing-card')).to_have_count(expected,timeout=30000)
   assert page.locator('.kodimali-promotions-more').count()==0
   assert not page.evaluate('document.documentElement.scrollWidth>innerWidth')
   if expected:
    expect(page.locator('.sponsored-card-rail')).to_have_count(1)
    assert page.locator('.sponsored-card-rail').evaluate('(el)=>getComputedStyle(el).overflowX')=='auto'
   video=page.locator('.sponsored-listing-card video').first
   playing=False
   if video.count():
    video.scroll_into_view_if_needed();page.wait_for_function('()=>[...document.querySelectorAll(".sponsored-listing-card video")].some(v=>!v.paused&&v.currentTime>0)',timeout=30000)
    assert video.evaluate('(v)=>v.muted&&v.autoplay&&v.loop');playing=True
   page.screenshot(path=f'design-previews/listing-location-ads/live-sponsored-{slug or "all"}-{width}.png')
   assert not errors,errors;results.append({'width':width,'path':path,'eligible_ads':expected,'autoplay':playing,'errors':list(errors)})
  ctx.close()
 browser.close()
Path('tmp/sponsored-live-results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
print('PASS live listing, category and Events ads match all eligible campaigns; muted autoplay and blocked storage work')
