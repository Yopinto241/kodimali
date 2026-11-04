"""Browser checks for Events operations. All Auth/PostgREST calls are fixtures."""
import base64,json,os,time
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright,expect

BASE=os.environ.get('REPAIR_WEB_BASE','http://127.0.0.1:3101')
USER='11111111-1111-4111-8111-111111111111'
PROFILE='22222222-2222-4222-8222-222222222222'
PLAN='33333333-3333-4333-8333-333333333333'
ITEM='44444444-4444-4444-8444-444444444444'

def seed(context,role,permissions,language):
    user={'id':USER,'aud':'authenticated','role':'authenticated','email':'repair@example.invalid','created_at':'2026-01-01T00:00:00Z'}
    enc=lambda x:base64.urlsafe_b64encode(json.dumps(x).encode()).decode().rstrip('=')
    expiry=int(time.time())+3600
    token=enc({'alg':'HS256','typ':'JWT'})+'.'+enc({'sub':USER,'exp':expiry,'aud':'authenticated'})+'.fixture'
    storage={'kodimali-language':language,'kodimali_browser_device_id':'repair-test','kodimali_welcome_seen_v1':'repair-test','sb-tlhoajedyaeaaqtrjqqh-auth-token':json.dumps({'access_token':token,'refresh_token':'fixture','token_type':'bearer','expires_in':3600,'expires_at':expiry,'user':user})}
    context.add_init_script('Object.entries('+json.dumps(storage)+').forEach(([key,value])=>localStorage.setItem(key,value));')
    calls=[]
    def api(route):
        path=urlparse(route.request.url).path
        body=route.request.post_data_json if route.request.method=='POST' else None
        calls.append((path,body,route.request.method))
        data=[]
        if path.endswith('/user'):data=user
        elif path.endswith('/user_roles'):data=[{'role':role}]
        elif path.endswith('/get_my_admin_permissions'):data=permissions
        elif path.endswith('/current_owner_id'):data=None
        elif path.endswith('/event_service_profiles'):data={'id':PROFILE,'profile_id':USER,'display_name':'Fixture Provider','verification_status':'verified'} if role=='agent' else []
        elif path.endswith('/event_tasks'):data=[{'id':ITEM,'plan_id':PLAN,'title':'Fixture delivery','assigned_profile_id':USER,'status':'pending'}]
        elif path.endswith('/event_disputes'):data=[{'id':ITEM,'plan_id':PLAN,'reason':'Fixture dispute','status':'open'}]
        elif path.endswith('/event_plans'):data=[{'id':PLAN,'reference':'EV-FIXTURE','title':'Fixture event','status':'fully_confirmed','event_period':'Fixture date','event_plan_items':[{'id':ITEM,'item_kind':'equipment','status':'provider_confirmed','requested_quantity':2}]}]
        route.fulfill(status=200,content_type='application/json',body=json.dumps(data))
    context.route('**/auth/v1/**',api)
    context.route('**/rest/v1/**',api)
    return calls

with sync_playwright() as pw:
    browser=pw.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe')
    for width,language in [(390,'en'),(1440,'sw')]:
        context=browser.new_context(viewport={'width':width,'height':1000},reduced_motion='reduce')
        calls=seed(context,'admin',['analytics.view'],language)
        page=context.new_page();page.goto(BASE+'/manage/events-coordinator/plans')
        expect(page.get_by_role('alert')).to_be_visible()
        assert not any('/event_' in path for path,_,_ in calls)
        print(f'PASS: denied analyst cannot fetch Events workspace data ({width}/{language})')
        context.close()
    context=browser.new_context(viewport={'width':390,'height':1000},reduced_motion='reduce')
    calls=seed(context,'agent',[],'en');page=context.new_page();page.goto(BASE+'/manage/events-provider/services')
    page.get_by_text('Add service',exact=True).click()
    form=page.locator('form').filter(has=page.locator('input[name="duration_minutes"]'))
    form.locator('[name="title"]').fill('Fixture photography')
    form.locator('[name="description"]').fill('Fixture service description')
    form.locator('[name="price_amount_tzs"]').fill('12000')
    form.locator('[name="duration_minutes"]').fill('60')
    form.get_by_role('button',name='Save',exact=True).click()
    expect(page.get_by_role('status').filter(has_text='Changes saved.')).to_be_visible()
    write=next(body for path,body,method in calls if path.endswith('/event_service_offerings') and method=='POST')
    assert write['provider_id']==PROFILE and write['price_amount_tzs']==12000 and 'verification_status' not in write
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
    print('PASS: provider service creation uses own profile without approval bypass at mobile width')
    page.goto(BASE+'/manage/events-provider/tasks')
    page.get_by_text('Update fulfillment task',exact=True).click()
    form=page.locator('form').filter(has=page.locator('select[name="status"]'))
    form.locator('[name="status"]').select_option('completed')
    form.get_by_role('button',name='Save',exact=True).click()
    expect(page.get_by_role('status').filter(has_text='Changes saved.')).to_be_visible()
    assert any(path.endswith('/update_event_fulfillment_task') and body['p_task_id']==ITEM for path,body,_ in calls)
    print('PASS: provider fulfillment task uses narrow authenticated RPC')

    context.close()
    context=browser.new_context(viewport={'width':1440,'height':1000},reduced_motion='reduce')
    calls=seed(context,'admin',['events.manage','events.quotes'],'en');page=context.new_page();page.goto(BASE+'/manage/events-coordinator/plans')
    page.get_by_text('Send itemized quotation',exact=True).click()
    form=page.locator('form').filter(has=page.locator('input[name="additional"]'))
    form.locator('[name="price_'+ITEM+'"]').fill('1000')
    form.get_by_role('button',name='Save',exact=True).click()
    expect(page.get_by_role('status').filter(has_text='Changes saved.')).to_be_visible()
    args=next(body for path,body,_ in calls if path.endswith('/create_event_quote_revision'))
    assert args['p_plan_id']==PLAN and args['p_items'][0]['quantity']==2 and args['p_items'][0]['unit_price_tzs']==1000

    page.goto(BASE+'/manage/events-coordinator/support')
    page.get_by_text('Review dispute',exact=True).click()
    form=page.locator('form').filter(has=page.locator('textarea[name="resolution"]'))
    form.locator('[name="status"]').select_option('resolved')
    form.locator('[name="resolution"]').fill('Fixture resolution')
    form.get_by_role('button',name='Save',exact=True).click()
    expect(page.get_by_role('status').filter(has_text='Changes saved.')).to_be_visible()
    assert any(path.endswith('/resolve_event_dispute') and body['p_dispute_id']==ITEM for path,body,_ in calls)
    print('PASS: coordinator dispute review uses audited RPC')
    page.goto(BASE+'/manage/events-coordinator/finance')
    expect(page.get_by_text('Finance permission required',exact=True)).to_be_visible()
    assert not any(path.endswith('/financial_reconciliation_cases') for path,_,_ in calls)
    print('PASS: itemized quote uses canonical RPC; coordinator cannot read finance without finance permission')
    context.close();browser.close()
