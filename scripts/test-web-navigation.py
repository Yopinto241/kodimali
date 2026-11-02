"""Exercise real document navigation and storage denial without submitting app data."""
import os
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
BASE=os.environ.get('NAV_TEST_BASE','http://localhost:3000')
OUT=Path('tmp/navigation-checks');OUT.mkdir(parents=True,exist_ok=True)
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
 for width in [390,1440]:
  context=browser.new_context(viewport={'width':width,'height':900},reduced_motion='reduce')
  context.add_init_script("localStorage.setItem('kodimali-language','en');localStorage.setItem('kodimali_browser_device_id','nav-check');localStorage.setItem('kodimali_welcome_seen_v1','nav-check');")
  page=context.new_page();errors=[];documents=[];rsc=[]
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.on('request',lambda r:documents.append(r.url) if r.is_navigation_request() and r.frame==page.main_frame else None)
  # Poison client-transition responses: document navigation must not depend on these.
  def reject_rsc(route):
   if route.request.headers.get('rsc')=='1':rsc.append(route.request.url);route.fulfill(status=500,body='Simulated stale navigation response')
   else:route.continue_()
  context.route('**/*',reject_rsc)
  page.goto(BASE+'/events');expect(page.get_by_role('heading',name='Event equipment and professionals')).to_be_visible()
  for cycle in range(3):
   before=len(documents);page.locator('main a[href="/events/plan"]').first.click();page.wait_for_url('**/events/plan');expect(page.get_by_role('button',name='Continue',exact=True).first).to_be_enabled();assert len(documents)>before
   page.get_by_role('button',name='Back',exact=True).click();page.wait_for_url('**/events');expect(page.get_by_role('heading',name='Event equipment and professionals')).to_be_visible();assert page.locator('.navigation-progress').count()==0
  for destination in ['/listings','/account','/events']:
   links=page.locator(f'a[href="{destination}"]:visible');links.first.click();page.wait_for_timeout(1600)
   assert 'This page couldn' not in page.locator('body').inner_text();assert '__next_error__' != page.locator('html').get_attribute('id')
  assert not errors,errors
  assert not page.evaluate('document.documentElement.scrollWidth>innerWidth')
  page.screenshot(path=str(OUT/f'events-muted-{width}.png'),full_page=True)
  page.locator('main a[href="/events/plan"]').first.click();expect(page.get_by_role('heading',name='Plan your event',exact=True)).to_be_visible();page.screenshot(path=str(OUT/f'planner-muted-{width}.png'),full_page=True)
  print(f'PASS {width}px: repeated navigation/back, listings/account links, document loads with failed RSC, no error loop or overflow',flush=True)
  context.close()
 context=browser.new_context()
 context.add_init_script("Object.defineProperty(window,'localStorage',{get(){throw new DOMException('Storage disabled','SecurityError')}})")
 page=context.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.goto(BASE+'/events');page.wait_for_timeout(1800)
 page.keyboard.press('Escape')
 expect(page.get_by_role('heading',name='Vifaa na wataalamu wa matukio')).to_be_visible()
 page.locator('select[aria-label="Lugha"]:visible').first.select_option('en')
 expect(page.get_by_role('heading',name='Event equipment and professionals')).to_be_visible()
 for route in ['/listings','/compare']:
  page.goto(BASE+route);page.wait_for_timeout(1200);page.keyboard.press('Escape');assert page.locator('html').get_attribute('id')!='__next_error__'
 assert not errors,errors
 print('PASS blocked storage: no global error, page and language switching remain usable',flush=True)
 browser.close()
