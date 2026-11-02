"""Read-only mobile lab observations. These are not CrUX field Core Web Vitals or field INP."""
import argparse,json,time
from pathlib import Path
from playwright.sync_api import sync_playwright
parser=argparse.ArgumentParser();parser.add_argument('--base',default='https://kodimali.com');parser.add_argument('--out',default='tmp/seo-mobile-before.json');args=parser.parse_args()
observer="""window.__seo={lcp:0,cls:0,interactions:[]};
new PerformanceObserver(l=>{for(const e of l.getEntries())window.__seo.lcp=e.startTime}).observe({type:'largest-contentful-paint',buffered:true});
new PerformanceObserver(l=>{for(const e of l.getEntries())if(!e.hadRecentInput)window.__seo.cls+=e.value}).observe({type:'layout-shift',buffered:true});
new PerformanceObserver(l=>{for(const e of l.getEntries())if(e.interactionId)window.__seo.interactions.push(e.duration)}).observe({type:'event',buffered:true,durationThreshold:16});"""
results=[]
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
 for path,returning in [('/',False),('/',True),('/events',True)]:
  context=browser.new_context(viewport={'width':390,'height':844},device_scale_factor=1,is_mobile=True,reduced_motion='reduce')
  if returning:context.add_init_script("localStorage.setItem('kodimali_browser_device_id','seo-lab');localStorage.setItem('kodimali_welcome_seen_v1','seo-lab');")
  context.add_init_script(observer);page=context.new_page();cdp=context.new_cdp_session(page)
  cdp.send('Network.enable');cdp.send('Network.setCacheDisabled',{'cacheDisabled':True});cdp.send('Network.emulateNetworkConditions',{'offline':False,'latency':150,'downloadThroughput':200000,'uploadThroughput':100000,'connectionType':'cellular4g'});cdp.send('Emulation.setCPUThrottlingRate',{'rate':4})
  started=time.monotonic();response=page.goto(args.base+path,wait_until='load',timeout=90000);page.wait_for_timeout(4000)
  button=page.get_by_role('button',name='Sitisha',exact=True)
  if not returning and page.get_by_role('button',name='Funga',exact=True).count():page.keyboard.press('Escape');page.wait_for_timeout(300)
  elif button.count():button.click();page.wait_for_timeout(300)
  metrics=page.evaluate("""()=>({...window.__seo,navigation:performance.getEntriesByType('navigation').map(e=>({ttfb:e.responseStart,dcl:e.domContentLoadedEventEnd,load:e.loadEventEnd}))[0],resources:performance.getEntriesByType('resource').map(e=>({name:e.name,bytes:e.transferSize,type:e.initiatorType})),overflow:document.documentElement.scrollWidth>innerWidth,heroImages:document.querySelectorAll('.cinematic-hero img').length,missingImageAlt:document.querySelectorAll('img:not([alt])').length,h1:document.querySelectorAll('h1').length,main:document.querySelectorAll('main').length})""")
  row={'url':args.base+path,'returning':returning,'status':response.status,'elapsed_seconds':round(time.monotonic()-started,2),**metrics};results.append(row)
  print(json.dumps({k:v for k,v in row.items() if k!='resources'}),flush=True);context.close()
 browser.close()
Path(args.out).write_text(json.dumps(results,indent=2),encoding='utf-8')
