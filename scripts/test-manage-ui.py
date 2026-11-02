"""Management browser acceptance checks using isolated fixture sessions and API data."""
import base64, json, os, time, re
from pathlib import Path
from urllib.parse import urlparse, parse_qs
from playwright.sync_api import sync_playwright, expect

expect.set_options(timeout=30000)
BASE = os.environ.get('MANAGE_TEST_BASE', 'http://127.0.0.1:3101')
OUT = Path('design-previews/manage-redesign'); OUT.mkdir(parents=True, exist_ok=True)
USER = '11111111-1111-4111-8111-111111111111'
def uid(n): return '10000000-0000-4000-8000-'+str(n).zfill(12)
LOCATIONS = [dict(id=uid(n),parent_id=uid(n-1) if n>1 else None,name=name,location_type=kind,is_active=True) for n,name,kind in [(1,'Tanzania','country'),(2,'Arusha','region'),(3,'Arusha District','district'),(4,'Sokoni','ward'),(5,'Central','area')]]
CUSTOMERS = [dict(id=uid(n+100),full_name=f'Customer {n}',account_email=f'customer{n}@example.invalid',phone_number='255700000000',preferred_language='sw',email_confirmed_at='2026-01-01T00:00:00Z' if n%2 else None,created_at='2026-01-01T00:00:00Z',updated_at='2026-01-01T00:00:00Z') for n in range(1,46)]
LISTINGS = [dict(id=uid(n+200),title=f'Apartment {n}',description='Fixture apartment description',price_amount=150000,price_period='month',status='active',availability_status='available',public_location_label='Arusha / Sokoni',listing_media=[],asset_categories={'id':uid(90),'name':'Apartment','slug':'apartment'}) for n in range(1,26)]

def seed(context, permissions=None, role='admin'):
    permissions = ['*'] if permissions is None else permissions
    expiry=int(time.time())+3600
    enc=lambda obj:base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip('=')
    token=enc({'alg':'HS256','typ':'JWT'})+'.'+enc({'sub':USER,'exp':expiry,'aud':'authenticated'})+'.fixture'
    user={'id':USER,'aud':'authenticated','role':'authenticated','email':'ui-fixture@example.invalid','created_at':'2026-01-01T00:00:00Z'}
    storage={'kodimali-language':'en','sb-tlhoajedyaeaaqtrjqqh-auth-token':json.dumps({'access_token':token,'refresh_token':'fixture','token_type':'bearer','expires_in':3600,'expires_at':expiry,'user':user})}
    context.add_cookies([{'name':'kodimali_language','value':'en','url':BASE}])
    context.add_init_script('Object.entries('+json.dumps(storage)+').forEach(([key,value])=>{if(localStorage.getItem(key)===null)localStorage.setItem(key,value)});')
    requests=[]; locations=[dict(row) for row in LOCATIONS]
    def api(route):
        req=route.request; url=urlparse(req.url); path=url.path; query=parse_qs(url.query); body=req.post_data_json if req.post_data else {}
        requests.append((path,query,body)); data=[]
        if path.endswith('/user_roles'): data=[{'role':role}]
        elif path.endswith('/get_my_admin_permissions'): data=permissions
        elif path.endswith('/get_my_supervisor_context'): data={'scoped':'supervisor.scoped' in permissions,'active':True,'supervisor_id':USER,'location_id':uid(2),'location_name':'Arusha','location_type':'region'}
        elif path.endswith('/get_supervisor_directory'): data=[]
        elif path.endswith('/get_manage_dashboard_counts'): data={'listings':25,'requests':4,'agents':2}
        elif path.endswith('/search_manage_customers'):
            data=CUSTOMERS
            if body.get('p_id'): data=[row for row in data if row['id']==body['p_id']]
            if body.get('p_search'): data=[row for row in data if body['p_search'].lower() in str(row).lower()]
            if body.get('p_confirmation'): data=[row for row in data if bool(row['email_confirmed_at'])==(body['p_confirmation']=='confirmed')]
            data=data[body.get('p_offset',0):body.get('p_offset',0)+body.get('p_limit',20)]
        elif path.endswith('/agents'): data={'id':uid(70)} if role=='agent' else []
        elif path.endswith('/asset_categories'): data=[{'id':uid(90),'name':'Apartment'}]
        elif path.endswith('/listings'):
            data=LISTINGS
            if 'id' in query: data=[row for row in data if row['id']==query['id'][0][3:]]
            if query.get('title'): data=[row for row in data if query['title'][0].removeprefix('ilike.').strip('%').lower() in row['title'].lower()]
            if query.get('status'): data=[row for row in data if row['status']==query['status'][0][3:]]
            start=int(query.get('offset',['0'])[0]); data=data[start:start+int(query.get('limit',['20'])[0])]
        elif path.endswith('/locations'):
            if req.method=='POST': locations.append(dict(body,id=uid(99),is_active=True))
            if req.method=='PATCH':
                for row in locations:
                    if row['id']==query['id'][0][3:]: row.update(body)
            if query.get('location_type')==['eq.country']: data=LOCATIONS[0] if 'vnd.pgrst.object' in req.headers.get('accept','') else [LOCATIONS[0]]
            elif query.get('location_type')==['eq.region']: data=[LOCATIONS[1]]
            elif query.get('id'): data=next((row for row in locations if row['id']==query['id'][0][3:]),None)
            else:
                parent=query.get('parent_id',['is.null'])[0]
                data=[row for row in locations if row['parent_id']==(None if parent=='is.null' else parent[3:])]
                if query.get('name'): data=[row for row in data if row['name'].lower()==query['name'][0].removeprefix('ilike.').lower()]
                if query.get('id',[''])[0].startswith('neq.'): data=[row for row in data if row['id']!=query['id'][0][4:]]
        route.fulfill(status=200,content_type='application/json',body=json.dumps(data))
    context.route('**/rest/v1/**',api)
    context.route('**/auth/v1/user',lambda route:route.fulfill(status=200,content_type='application/json',body=json.dumps(user)))
    return requests

def assert_layout(page):
    colors=page.evaluate("""() => [...document.querySelectorAll('.manage-content .btn-success:not(:disabled),.manage-page-heading h1')].map(el=>{const fg=getComputedStyle(el).color;let node=el,bg='';while(node){bg=getComputedStyle(node).backgroundColor;if(bg!=='rgba(0, 0, 0, 0)')break;node=node.parentElement;}return {fg,bg};})""")
    def lum(color):
        values=[float(v)/255 for v in re.findall(r'[0-9.]+',color)[:3]]
        values=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in values]
        return sum(v*w for v,w in zip(values,[.2126,.7152,.0722]))
    for pair in colors:
        a,b=sorted([lum(pair['fg']),lum(pair['bg'])]); assert (b+.05)/(a+.05)>=4.5,pair

    assert not page.evaluate('document.documentElement.scrollWidth>innerWidth'), page.url
    assert page.locator('h1').first.evaluate('(el)=>el.getBoundingClientRect().top') < 170

with sync_playwright() as pw:
    browser=pw.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
    for width in [320,375,390,430,768,1440]:
        ctx=browser.new_context(viewport={'width':width,'height':900},reduced_motion='reduce'); requests=seed(ctx); page=ctx.new_page(); errors=[]; rsc_requests=[]; page.on('pageerror',lambda error:errors.append(str(error))); page.on('request',lambda request:rsc_requests.append(request.url) if request.headers.get('rsc')=='1' else None)
        for section in ['', '/users', '/listings', '/locations']:
            page.goto(BASE+'/manage'+section); expect(page.locator('.manage-header')).to_be_visible(); expect(page.locator('.navigation-progress')).to_have_count(0); assert_layout(page)
            if section=='/users': expect(page.get_by_text('customer1@example.invalid')).to_be_visible()
            if section=='/listings': expect(page.get_by_role('link',name='Apartment 1',exact=True)).to_be_visible()
            if section=='/locations': expect(page.locator('article').get_by_role('link',name='Arusha \u2192',exact=True)).to_be_visible()
            if width in [390,1440]: page.screenshot(path=str(OUT/f'{section.strip("/") or "dashboard"}-{width}.png'),full_page=True)
        page.goto(BASE+'/manage');
        if width<960: page.get_by_role('button',name='Menu',exact=True).click()
        page.locator('#manage-navigation').get_by_role('link',name='Users',exact=True).click(); expect(page).to_have_url(BASE+'/manage/users?workspace=admin'); expect(page.get_by_text('customer1@example.invalid')).to_be_visible()
        page.get_by_role('link',name='Next',exact=True).click(); expect(page.get_by_text('customer21@example.invalid')).to_be_visible(); page.reload(); expect(page.get_by_text('customer21@example.invalid')).to_be_visible()
        page.get_by_placeholder('Name, email or phone').fill('customer45@example.invalid'); page.get_by_role('button',name='Search',exact=True).click(); expect(page.get_by_text('customer45@example.invalid')).to_be_visible(); page.get_by_role('link',name='Customer 45',exact=True).click(); expect(page.get_by_text('Preferred language',exact=True)).to_be_visible(); page.go_back(); expect(page.get_by_placeholder('Name, email or phone')).to_have_value('customer45@example.invalid')
        page.goto(BASE+'/manage/listings?page=1'); expect(page.get_by_role('link',name='Apartment 21',exact=True)).to_be_visible(); page.get_by_role('link',name='Apartment 21',exact=True).click(); expect(page.get_by_text('Fixture apartment description')).to_be_visible(); page.get_by_role('link',name='Back to listings').click(); expect(page).to_have_url(BASE+'/manage/listings?page=1')
        page.goto(BASE+'/manage/locations')
        for name in ['Arusha','Arusha District','Sokoni']:
            page.locator('article').get_by_role('link',name=name+' →',exact=True).click()
        expect(page.locator('article').get_by_role('link',name='Central →')).to_be_visible()
        assert_layout(page)
        if width==390: page.screenshot(path=str(OUT/'locations-hierarchy-390.png'),full_page=True)
        page.get_by_role('button',name=re.compile(r'^Add area$',re.I)).click(); expect(page.get_by_role('dialog')).to_be_visible(); page.get_by_role('dialog').locator('input').fill('New Area'); page.get_by_role('button',name='Save',exact=True).click(); expect(page.get_by_role('dialog')).to_have_count(0); expect(page.locator('article').get_by_role('link',name='New Area →')).to_be_visible()
        inserts=[body for path,query,body in requests if path.endswith('/locations') and isinstance(body,dict) and body.get('name')=='New Area']; assert inserts[-1]['parent_id']==uid(4) and inserts[-1]['location_type']=='area'
        page.go_back(); expect(page.locator('article').get_by_role('link',name='Sokoni →')).to_be_visible(); assert not errors,errors; assert not rsc_requests,rsc_requests
        print('PASS responsive routes, search, pagination, details, location hierarchy and add at',width,flush=True); ctx.close()
    for role,permissions in [('admin',['payments.manage']),('agent',[])]:
        ctx=browser.new_context(viewport={'width':390,'height':900}); requests=seed(ctx,permissions,role); page=ctx.new_page(); page.goto(BASE+'/manage/users'); expect(page.get_by_text('Access unavailable',exact=True).last).to_be_visible(); assert not any(path.endswith('/search_manage_customers') for path,_,_ in requests); ctx.close()
    print('PASS denied admin and agent deep links never fetch customer records',flush=True)
    ctx=browser.new_context(viewport={'width':390,'height':900}); seed(ctx); page=ctx.new_page(); failed=[False]
    def fail_once(route):
        if not failed[0]: route.fulfill(status=503,content_type='application/json',body=json.dumps({'message':'Temporarily unavailable'}))
        else: route.fallback()
    page.route('**/rest/v1/locations?*',fail_once)
    page.goto(BASE+'/manage/locations'); expect(page.get_by_role('button',name='Retry',exact=True)).to_be_visible(); failed[0]=True; page.get_by_role('button',name='Retry',exact=True).click(); expect(page.locator('article').get_by_role('link',name='Arusha \u2192',exact=True)).to_be_visible()
    response=page.goto(BASE+'/manage/not-a-section'); assert 'noindex' in response.headers.get('x-robots-tag',''); expect(page.locator('main h1')).to_have_text('Page not found')
    ctx.close(); print('PASS location error recovery and invalid-route handling',flush=True)
    ctx=browser.new_context(viewport={'width':390,'height':900})
    supervisor_requests=seed(ctx,['agents.manage','supervisor.scoped'])
    created=[]
    def create_agent(route):
        created.append(route.request.post_data_json)
        route.fulfill(status=200,content_type='application/json',body=json.dumps({'success':True}))
    ctx.route('**/functions/v1/create-agent-account',create_agent)
    ctx.route('**/api/locations?*',lambda route:route.fulfill(status=200,content_type='application/json',body=json.dumps([LOCATIONS[2]])))
    page=ctx.new_page(); page.goto(BASE+'/manage/agents')
    page.get_by_role('button',name='Add agent',exact=True).click()
    form=page.locator('#add-agent-form form')
    for name,value in {'fullName':'Fixture Agent','username':'fixture_agent','phone':'255700000000','nida':'FIXTURE-NOT-REAL','businessName':'Fixture Services','password':'Fixture-Only-Password-241','confirmPassword':'Fixture-Only-Password-241'}.items():
        form.locator('[name="'+name+'"]').fill(value)
    form.locator('[name="categoryId"]').select_option(uid(90))
    for location_id in [uid(3),uid(4),uid(5)]:
        form.get_by_role('combobox',name='Choose location',exact=True).select_option(location_id)
    form.get_by_role('button',name='Create agent account',exact=True).click()
    expect(page.get_by_text('Agent account created. Review and activate the agent when verification is complete.',exact=True)).to_be_visible()
    assert len(created)==1 and created[0]['username']=='fixture_agent' and created[0]['location_id']==uid(5)
    assert not any(path.endswith('/get_supervisor_directory') for path,_,_ in supervisor_requests)
    assert page.evaluate('JSON.parse(localStorage.getItem("sb-tlhoajedyaeaaqtrjqqh-auth-token")).user.id')==USER
    assert_layout(page)
    ctx.close(); print('PASS Supervisor adds agent without replacing the staff session',flush=True)
    ctx=browser.new_context(viewport={'width':390,'height':900})
    seed(ctx,['agents.manage','supervisor.scoped'])
    ctx.route('**/rest/v1/rpc/get_my_supervisor_context',lambda route:route.fulfill(status=200,content_type='application/json',body=json.dumps({'scoped':True,'active':False})))
    page=ctx.new_page(); page.goto(BASE+'/manage/agents'); expect(page.get_by_role('button',name='Add agent',exact=True)).to_be_disabled()
    expect(page.get_by_text('Ask Super Admin to activate your supervisor territory before adding agents.',exact=True)).to_be_visible()
    page.goto(BASE+'/manage/locations'); expect(page.get_by_text('Access unavailable',exact=True).last).to_be_visible()
    ctx.close(); print('PASS supervisor without a territory fails closed and cannot manage locations',flush=True)
    ctx=browser.new_context(viewport={'width':390,'height':900}); seed(ctx)
    team_changes=[]; configurations=[]; team=[None]
    supervisors=[{'supervisor_id':uid(801),'full_name':'Supervisor A','account_email':'supervisor@example.invalid','location_id':uid(2),'location_name':'Arusha','is_active':True,'agent_count':0}]
    ctx.route('**/rest/v1/rpc/get_supervisor_directory',lambda route:route.fulfill(status=200,content_type='application/json',body=json.dumps(supervisors)))
    ctx.route('**/rest/v1/agents?*',lambda route:route.fulfill(status=200,content_type='application/json',body=json.dumps([{'id':uid(701),'display_name':'Assigned Agent','supervisor_id':team[0],'account_status':'inactive','verification_status':'pending'}])))
    def configure(route):
        configurations.append(route.request.post_data_json); route.fulfill(status=200,content_type='application/json',body='null')
    def transfer(route):
        body=route.request.post_data_json; team_changes.append(body); team[0]=body['p_supervisor_id']; route.fulfill(status=200,content_type='application/json',body='null')
    ctx.route('**/rest/v1/rpc/configure_supervisor_territory',configure)
    ctx.route('**/rest/v1/rpc/assign_agent_supervisor',transfer)
    page=ctx.new_page(); page.on('dialog',lambda dialog:dialog.accept()); page.goto(BASE+'/manage/agents')
    page.get_by_text('Supervisors and territories',exact=True).click()
    expect(page.get_by_text('Register as an agent first.',exact=False)).to_be_visible()
    page.get_by_role('textbox',name='Registered agent email').fill('supervisor@example.invalid')
    page.get_by_role('combobox',name='Choose location',exact=True).select_option(uid(1))
    page.get_by_role('combobox',name='Choose location',exact=True).select_option(uid(2))
    page.get_by_role('button',name='Assign supervisor territory',exact=True).click(); expect(page.get_by_text('Supervisor territory saved.',exact=True)).to_be_visible()
    assert configurations[-1]['p_location_id']==uid(2)
    page.get_by_role('combobox',name='Assigned supervisor',exact=True).select_option(uid(801))
    with page.expect_response('**/rest/v1/rpc/assign_agent_supervisor'):
        page.get_by_role('button',name='Save agent team',exact=True).click()
    expect(page.get_by_role('combobox',name='Assigned supervisor',exact=True)).to_have_value(uid(801))
    assert team_changes[-1]=={'p_agent_id':uid(701),'p_supervisor_id':uid(801)}
    assert_layout(page); ctx.close(); print('PASS Super Admin assigns territory and one exclusive agent supervisor',flush=True)
    browser.close()
