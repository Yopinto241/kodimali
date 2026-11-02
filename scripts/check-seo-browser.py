"""Read-only mobile accessibility observations and hero regression checks against a built preview."""
import json,os
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('SEO_BROWSER_BASE','http://127.0.0.1:3101');results=[]
with sync_playwright() as pw:
 browser=pw.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
 context=browser.new_context(viewport={'width':390,'height':844},reduced_motion='reduce');page=context.new_page();page.goto(BASE+'/')
 assert page.locator('.cinematic-hero img').count()==1
 close=page.get_by_role('button',name='Funga',exact=True);expect(close).to_be_visible();close.click();expect(page.get_by_role('dialog')).to_have_count(0);page.mouse.move(0,0)
 before=page.locator('.cinematic-hero h1').inner_text();page.wait_for_timeout(5100);assert page.locator('.cinematic-hero h1').inner_text()==before
 page.locator('.hero-tabs a').nth(2).focus();expect(page.locator('.cinematic-hero h1')).to_have_text('Unahitaji gari?');assert page.locator('.cinematic-hero img').count()<=3
 page.wait_for_function("document.querySelector('.cinematic-slide.is-active').naturalWidth > 0")
 assert page.locator('.listing-rails img[loading="eager"]').count()==0
 print('PASS mobile welcome close, one initial hero image, reduced motion, keyboard slide selection, real image load, lazy lower listings',flush=True)
 for path in ['/','/listings','/events','/events/plan','/listing/363d0a72-7151-4cbd-a037-c89daa03c499']:
  page.goto(BASE+path);page.wait_for_timeout(1200);page.add_script_tag(path='tmp/axe.min.js')
  result=page.evaluate("""async()=>{const r=await axe.run(document,{runOnly:{type:'tag',values:['wcag2a','wcag2aa','wcag21aa']}});return {violations:r.violations.map(v=>({id:v.id,impact:v.impact,description:v.description,nodes:v.nodes.map(n=>({target:n.target,summary:n.failureSummary}))})),passes:r.passes.length,incomplete:r.incomplete.map(v=>v.id)}}""")
  row={'path':path,**result,'overflow':page.evaluate('document.documentElement.scrollWidth>innerWidth'),'brokenVisibleImages':page.locator('img').evaluate_all('(images)=>images.filter(i=>i.complete&&i.currentSrc&&!i.naturalWidth&&i.getBoundingClientRect().top<innerHeight).map(i=>i.alt)')};results.append(row)
  print(path,'axe violations',[(v['id'],v['impact'],len(v['nodes'])) for v in result['violations']],'overflow',row['overflow'],'broken images',row['brokenVisibleImages'],flush=True)
 context.close()
 context=browser.new_context(viewport={'width':1440,'height':900});context.add_init_script("localStorage.setItem('kodimali_browser_device_id','seo-animation');localStorage.setItem('kodimali_welcome_seen_v1','seo-animation');")
 page=context.new_page();page.goto(BASE+'/');before=page.locator('.cinematic-hero h1').inner_text();page.wait_for_timeout(5200);assert page.locator('.cinematic-hero h1').inner_text()!=before
 page.get_by_role('button',name='Sitisha',exact=True).click();before=page.locator('.cinematic-hero h1').inner_text();page.wait_for_timeout(5200);assert page.locator('.cinematic-hero h1').inner_text()==before
 print('PASS normal-motion hero advances and pause holds the current slide',flush=True);browser.close()
Path('tmp/seo-accessibility.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
