"""Responsive public browsing and contact-gate tests. Payments and metrics are mocked."""
import json, os, re, time
from pathlib import Path
from urllib.parse import urlparse,parse_qs
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('LISTING_TEST_BASE','http://127.0.0.1:3101')
OUT=Path('design-previews/listing-location-ads');OUT.mkdir(parents=True,exist_ok=True)
expect.set_options(timeout=30000)
def contrast(locator):
    pair=locator.evaluate('(el)=>[getComputedStyle(el).color,getComputedStyle(el).backgroundColor]')
    def lum(value):
        c=[float(v)/255 for v in re.findall(r'[0-9.]+',value)[:3]]
        c=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in c]
        return sum(v*w for v,w in zip(c,[.2126,.7152,.0722]))
    low,high=sorted(map(lum,pair));assert (high+.05)/(low+.05)>=4.5,pair
def seed(ctx):
    ctx.add_cookies([{'name':'kodimali_language','value':'en','url':BASE}])
    ctx.add_init_script("localStorage.setItem('kodimali_browser_device_id','audit');localStorage.setItem('kodimali_welcome_seen_v1','audit');localStorage.setItem('kodimali-language','en');Object.defineProperty(window,'sessionStorage',{get(){throw new Error('blocked storage')}})")
    events=[]
    def record(route):
        events.append(route.request.post_data_json);route.fulfill(status=200,content_type='application/json',body='null')
    ctx.route('**/rest/v1/rpc/record_platform_promotion_event',record)
    return events
with sync_playwright() as pw:
    browser=pw.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
    listing_id=None
    for width in [320,390,768,1440]:
        ctx=browser.new_context(viewport={'width':width,'height':900});events=seed(ctx);page=ctx.new_page();errors=[]
        page.on('pageerror',lambda error:errors.append(str(error)))
        page.goto(BASE+'/listings');expect(page.locator('.listing-location-trigger')).to_be_visible()
        if not listing_id:
            links=page.locator('a[href*="/listing/"]').evaluate_all('(els)=>els.map(el=>el.getAttribute("href"))')
            listing_id=next(re.search(r'/listing/([0-9a-f-]{36})',link).group(1) for link in links if re.search(r'/listing/([0-9a-f-]{36})',link))
        assert not page.evaluate('document.documentElement.scrollWidth>innerWidth')
        links=page.locator('a.listing-whatsapp-action')
        if links.count():
            assert links.count()==3
            assert all(link.endswith('/contact?intent=whatsapp') for link in links.evaluate_all('(els)=>els.map(el=>el.getAttribute("href"))'))
        page.locator('.listing-location-trigger').click();dialog=page.locator('dialog[open]');expect(dialog).to_be_visible()
        box=dialog.bounding_box();assert box['x']>=0 and box['x']+box['width']<=width+1,box
        assert box['y']>=0 and box['y']+box['height']<=901,box
        expect(dialog.get_by_label('Ward',exact=True)).to_be_visible();expect(dialog.get_by_label('Area',exact=True)).to_be_visible()
        contrast(dialog.get_by_role('button',name='Show results',exact=True))
        page.screenshot(path=str(OUT/f'location-{width}.png'))
        page.keyboard.press('Escape');expect(dialog).to_have_count(0)
        ad=page.locator('.kodimali-promotion-card').first
        if ad.count():
            assert not events,'Ads below results must not count impressions on mount'
            ad.scroll_into_view_if_needed();page.wait_for_timeout(1250)
            assert len(events)==1 and events[0]['p_event_type']=='impression',events
            assert ad.bounding_box()['height']<550,ad.bounding_box()
            expect(ad.get_by_role('link',name='Browse listings')).to_have_attribute('href','/listings')
            contrast(ad.get_by_role('link',name='Browse listings'))
            more=page.get_by_role('button',name=re.compile('More sponsored ads'))
            if more.count():
                assert page.locator('.kodimali-promotion-card').count()==1
                more.click();assert page.locator('.kodimali-promotion-card').count()>1
                assert len(events)==1,'Concealed ad must not count an impression'
            page.screenshot(path=str(OUT/f'ads-{width}.png'))
        assert not errors,errors
        ctx.close();print('PASS responsive dialog, compact ads, blocked storage:',width,flush=True)

    ctx=browser.new_context(viewport={'width':390,'height':900});seed(ctx);page=ctx.new_page()
    # Mock hierarchy child responses, never edit production locations.
    failure=[False]
    delayed=[];hold_parent=[None]
    def locations(route):
        q=parse_qs(urlparse(route.request.url).query);kind=q.get('locationType',[''])[0];parent=q.get('parentId',[''])[0]
        if parent==hold_parent[0]:delayed.append(route);return
        if failure[0]:route.fulfill(status=503,body='unavailable');return
        route.fulfill(status=200,content_type='application/json',body=json.dumps([{'id':parent+'-'+kind,'name':'Fixture '+kind}]))
    page.route('**/api/locations?*',locations)
    page.goto(BASE+'/listings');page.locator('.listing-location-trigger').click();dialog=page.locator('dialog[open]')
    region=dialog.get_by_label('Region',exact=True);rid=region.locator('option').nth(1).get_attribute('value');other=region.locator('option').nth(2).get_attribute('value')
    hold_parent[0]=rid;region.select_option(rid);page.wait_for_timeout(100);region.select_option(other)
    expect(dialog.get_by_label('District',exact=True)).to_be_enabled()
    for route in delayed:route.fulfill(status=200,content_type='application/json',body=json.dumps([{'id':'stale','name':'Stale district'}]))
    expect(dialog.get_by_label('District',exact=True).locator('option[value="'+other+'-district"]')).to_have_count(1)
    expect(dialog.get_by_label('District',exact=True).locator('option[value=stale]')).to_have_count(0)
    hold_parent[0]=None
    page.goto(BASE+'/listings?category=house&sort=price_low');page.locator('input[name=q]').fill('viti')
    page.locator('.search-price-filter summary').click()
    page.locator('input[name=minPrice]').fill('10000',force=True)
    page.locator('.listing-location-trigger').click();dialog=page.locator('dialog[open]')
    region=dialog.get_by_label('Region',exact=True);rid=region.locator('option').nth(1).get_attribute('value');region.select_option(rid)
    district=dialog.get_by_label('District',exact=True);expect(district).to_be_enabled();district.select_option(rid+'-district')
    ward=dialog.get_by_label('Ward',exact=True);expect(ward).to_be_enabled();ward.select_option(rid+'-district-ward')
    area=dialog.get_by_label('Area',exact=True);expect(area).to_be_enabled();area.select_option(rid+'-district-ward-area')
    dialog.get_by_role('button',name='Show results',exact=True).click();page.wait_for_url('**/listings?*')
    q=parse_qs(urlparse(page.url).query)
    assert q['q']==['viti'] and q['minPrice']==['10000'] and q['wardId']==[rid+'-district-ward'] and q['areaId']==[rid+'-district-ward-area'],q
    assert q['category']==['house'] and q['sort']==['price_low'],q
    page.goto(BASE+'/listings');page.locator('.listing-location-trigger').click();dialog=page.locator('dialog[open]');failure[0]=True
    dialog.get_by_label('Region',exact=True).select_option(rid);expect(dialog.get_by_role('alert')).to_be_visible();expect(dialog.get_by_role('button',name='Show results')).to_be_disabled()
    failure[0]=False;dialog.get_by_role('button',name='Retry',exact=True).click();expect(dialog.get_by_role('alert')).to_have_count(0)
    dialog.get_by_role('button',name='All locations',exact=True).click();page.wait_for_url('**/listings*');assert 'regionId=' not in page.url
    ctx.close();print('PASS hierarchy, draft filter preservation, error/retry, all locations',flush=True)

    assert listing_id
    for status in ['pending','expired','completed']:
        ctx=browser.new_context(viewport={'width':390,'height':900});seed(ctx);page=ctx.new_page();checks=[];wa=[]
        session={'payment_id':'fixture-payment','access_token':'fixture-token','status':'completed','phone_number':'255700000001'}
        ctx.add_init_script('localStorage.setItem('+json.dumps('kodimali-web-contact-access:'+listing_id)+','+json.dumps(json.dumps(session))+')')
        def payment(route):
            checks.append(route.request.post_data_json)
            route.fulfill(status=200,content_type='application/json',body=json.dumps({'paymentStatus':status,'phoneNumber':'0712 345 678' if status=='completed' else None}))
        ctx.route('**/api/listing-contact-payment/status',payment)
        ctx.route('https://wa.me/**',lambda route:(wa.append(route.request.url),route.fulfill(status=200,content_type='text/html',body='<h1>Fixture WhatsApp</h1>')))
        ctx.route('**/api/listing-contact-payment',lambda route:(_ for _ in ()).throw(AssertionError('No payment must be created by these tests')))
        page.goto(BASE+f'/listing/{listing_id}/contact?intent=whatsapp');page.wait_for_timeout(1800)
        assert checks,'Saved unlock must be checked with the server'
        if status=='completed':
            expect(page).to_have_url('https://wa.me/255712345678');assert wa
        else:
            assert not wa and 'wa.me' not in page.url
            assert '255700000001' not in page.locator('body').inner_text()
        ctx.close();print('PASS paid WhatsApp contact gate:',status,flush=True)
    browser.close()
