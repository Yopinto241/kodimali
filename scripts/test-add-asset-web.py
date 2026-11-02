"""Isolated add-asset acceptance test; all authenticated APIs and storage are mocked."""
import base64,json,os,time
from pathlib import Path
from urllib.parse import urlparse,parse_qs
from playwright.sync_api import sync_playwright,expect
expect.set_options(timeout=30000)
BASE=os.environ.get('ASSET_TEST_BASE','http://127.0.0.1:3101')
USER='11111111-1111-4111-8111-111111111111'
def uid(n):return '70000000-0000-4000-8000-'+str(n).zfill(12)
locations=[dict(id=uid(n),parent_id=uid(n-1) if n>1 else None,name=name,location_type=kind) for n,name,kind in [(1,'Tanzania','country'),(2,'Arusha','region'),(3,'Arusha District','district'),(4,'Sokoni','ward')]]
with sync_playwright() as pw:
 # Use HTTP/1.1 for the intercepted requests in this browser acceptance test.
 browser=pw.chromium.launch(executable_path='C:/Users/user/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe',args=['--disable-http2'])
 for width,mode in [(390,"free"),(1440,"paid"),(390,"approval"),(390,"switchfree"),(1440,"zeroplan")]:
  print('START',width,mode,flush=True)
  context=browser.new_context(viewport={'width':width,'height':900});expiry=int(time.time())+3600
  enc=lambda obj:base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip('=')
  token=enc({'alg':'HS256'})+'.'+enc({'sub':USER,'exp':expiry,'aud':'authenticated'})+'.fixture'
  user={'id':USER,'aud':'authenticated','role':'authenticated','email':'fixture@example.invalid'}
  storage={'kodimali-language':'en','kodimali_browser_device_id':'audit','kodimali_welcome_seen_v1':'audit','sb-tlhoajedyaeaaqtrjqqh-auth-token':json.dumps({'access_token':token,'refresh_token':'fixture','token_type':'bearer','expires_at':expiry,'expires_in':3600,'user':user})}
  context.add_init_script('Object.entries('+json.dumps(storage)+').forEach(([k,v])=>localStorage.setItem(k,v))')
  context.add_cookies([{'name':'kodimali_language','value':'en','url':BASE}])
  drafts=[];media=[];uploads=[];failed=[False];status=["draft"];payment_calls=[];fee_enabled=[mode in ["paid","switchfree"]]
  def api(route):
   req=route.request;path=urlparse(req.url).path;q=parse_qs(urlparse(req.url).query);body=req.post_data_json if req.post_data else {};data=[]
   if path.endswith('/user_roles'):data=[{'role':'agent'},{'role':'admin'}]
   elif path.endswith('/get_my_admin_permissions'):data=['supervisor.scoped','agents.manage']
   elif path.endswith('/get_my_supervisor_context'):data={'scoped':True,'active':True}
   elif path.endswith('/agents'):data={'id':uid(70)}
   elif path.endswith('/agent_service_categories'):data=[{'asset_categories':{'id':uid(90),'name':'Equipment','slug':'equipment','field_schema':[{'key':'notes','label':'Notes','type':'textarea'}]}}]
   elif path.endswith('/locations'):
    parent=q.get('parent_id',[''])[0].removeprefix('eq.')
    data=[r for r in locations if r['parent_id']==parent] if parent else [locations[0]]
   elif path.endswith('/ensure_ward_area'):
    assert body['p_ward_id']==uid(4);data=[{'id':uid(5),'parent_id':uid(4),'location_type':'area'}]
   elif path.endswith('/create_agent_listing_draft'):
    drafts.append(body);data=uid(200)
   elif path.endswith('/get_agent_listing_publication_mode'):data=[{'payment_required':fee_enabled[0],'amount_tzs':500 if fee_enabled[0] else 0,'admin_approval_required':mode in ['approval','switchfree']}]
   elif path.endswith('/agent_listing_payments'):data=None
   elif path.endswith('/listings'):
    if req.method=='PATCH':status[0]=body['status']
    row={'id':uid(200),'agent_id':uid(70),'title':'Fixture chairs','description':'Chairs available for events','public_location_label':'Sokoni','price_amount':5000,'price_period':'month','status':status[0],'availability_status':'available','publication_review_status':'pending' if mode in ['approval','switchfree'] else 'auto_approved','removed_reason':None,'removed_from_market_at':None,'listing_media':[],'asset_categories':{'name':'Equipment','slug':'equipment'}}
    data=row if 'application/vnd.pgrst.object+json' in req.headers.get('accept','') else [row] if drafts else []
   elif path.endswith('/listing_media'):
    if req.method=='POST':media.append(body)
    else:data=[{'id':uid(300)}] if any(m['storage_path']==q.get('storage_path',[''])[0].removeprefix('eq.') for m in media) else []
   route.fulfill(status=200,content_type='application/json',body=json.dumps(data))
  context.route('**/rest/v1/**',api)
  def publication(route):
   body=route.request.post_data_json;payment_calls.append((route.request.url,body))
   assert len(media)==1
   assert status[0]=='inactive'
   if route.request.url.endswith('create-agent-listing-payment'):
    assert body['listing_id']==uid(200)
    if fee_enabled[0]:
     data={'success':True,'paymentRequired':True,'paymentStatus':'pending','paymentId':uid(400)}
     if mode=='switchfree':fee_enabled[0]=False
    else:
     if mode in ['free','zeroplan']:status[0]='active'
     data={'success':True,'paymentRequired':False,'paymentStatus':'free','published':mode=='free'}
   else:
    assert body['payment_id']==uid(400);status[0]='active';data={'success':True,'paymentStatus':'paid'}
   route.fulfill(status=200,content_type='application/json',body=json.dumps(data))
  context.route('**/functions/v1/*agent-listing-payment',publication)
  context.route('**/auth/v1/**',lambda r:r.fulfill(status=200,content_type='application/json',body=json.dumps(user)))
  def upload(route):
   uploads.append(route.request.url)
   if not failed[0]:failed[0]=True;route.fulfill(status=503,body='temporary');return
   assert route.request.headers['content-type']=='image/jpeg'
   assert route.request.post_data_buffer[:2]==b'\xff\xd8'
   route.fulfill(status=200,content_type='application/json',body='{}')
  context.route('**/storage/v1/object/listing-media/**',upload)
  page=context.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  pending=set()
  page.on('request',lambda r:pending.add(urlparse(r.url).path))
  page.on('requestfinished',lambda r:pending.discard(urlparse(r.url).path))
  page.goto(BASE+'/manage/add-listing',wait_until='commit',timeout=60000)
  form=page.locator('form').filter(has=page.locator('input[type=file]'))
  try:expect(form).to_be_visible(timeout=30000)
  except:
   print('LOAD DIAGNOSTIC',page.evaluate('document.readyState'),sorted(pending),errors,flush=True)
   raise
  form.get_by_role('textbox',name='Title',exact=True).fill('Fixture chairs')
  form.get_by_role('textbox',name='Description',exact=True).fill('Chairs available for events')
  form.locator('select').filter(has=page.locator('option[value="'+uid(90)+'"]')).select_option(uid(90))
  for n in range(1,5):form.locator('select').filter(has=page.locator(f'option[value="{uid(n)}"]')).select_option(uid(n))
  form.locator('input[maxlength="100"]').fill('New fixture area')
  form.get_by_role('spinbutton',name='Price (TZS)',exact=True).fill('5000')
  form.get_by_role('textbox',name='Additional details',exact=True).fill('Delivery available on request')
  png=page.evaluate('''async()=>{const c=document.createElement('canvas');c.width=2600;c.height=1800;c.getContext('2d').fillRect(0,0,c.width,c.height);return Array.from(new Uint8Array(await (await new Promise(r=>c.toBlob(r,'image/png'))).arrayBuffer()))}''')
  form.locator('input[type=file]').set_input_files({'name':'chairs.png','mimeType':'image/png','buffer':bytes(png)})
  expect(form.locator('img')).to_have_count(1)
  form.get_by_role('button',name='Remove image').click()
  expect(form.locator('img')).to_have_count(0)
  form.locator('input[type=file]').set_input_files({'name':'chairs.png','mimeType':'image/png','buffer':bytes(png)})
  expect(form.locator('img')).to_have_count(1)
  Path('design-previews/add-asset').mkdir(parents=True,exist_ok=True)
  page.screenshot(path=f'design-previews/add-asset/form-{width}.png',full_page=True)
  button=form.get_by_role('button',name='Upload asset',exact=True);expect(button).to_be_enabled();button.click()
  expect(form.get_by_text('We could not finish saving. If a draft was created, retry here to finish its images. Check My listings before starting another draft.')).to_be_visible()
  expect(button).to_be_enabled();button.click()
  expect(form).to_have_count(0,timeout=30000)
  assert len(drafts)==1,drafts
  assert drafts[0]['p_location_id']==uid(5)
  assert 'Delivery available on request' in drafts[0]['p_description']
  assert len(media)==1 and media[0]['is_cover'] is True
  assert uploads[0]==uploads[1]
  expect(page.get_by_text('Asset uploaded',exact=True)).to_be_visible()
  page.get_by_role('button',name='Submit listing',exact=True).click()
  if mode in ['paid','switchfree']:
   expect(page.get_by_text('Confirm the payment request on your agent phone, then check payment.')).to_be_visible()
   page.get_by_role('button',name='Check payment',exact=True).click()
  expect(page.get_by_text('Listing uploaded. Awaiting approval.' if mode in ['approval','switchfree'] else 'Listing uploaded and published.',exact=True)).to_be_visible()
  assert len([r for r in payment_calls if r[0].endswith('create-agent-listing-payment')])==(2 if mode=='switchfree' else 1)
  if mode=='switchfree':assert not any(r[0].endswith('check-agent-listing-payment') for r in payment_calls)
  assert not errors,errors
  page.get_by_role('link',name='My listings',exact=True).click()
  page.wait_for_url('**/manage/listings*',wait_until='commit')
  expect(page.locator('.manage-header')).to_be_visible()
  page.get_by_role('link',name='Fixture chairs',exact=True).click()
  page.wait_for_url('**/manage/listings/'+uid(200)+'*',wait_until='commit')
  expect(page.get_by_role('heading',name='Fixture chairs',exact=True)).to_be_visible()
  page.reload(wait_until='commit',timeout=60000)
  expect(page.get_by_role('heading',name='Fixture chairs',exact=True)).to_be_visible()
  if mode in ['approval','switchfree']:
   page.get_by_role('button',name='Submit listing',exact=True).click()
   expect(page.get_by_text('Listing uploaded. Awaiting approval.',exact=True)).to_be_visible()
  else:expect(page.get_by_role('button',name='Submit listing',exact=True)).to_have_count(0)
  assert len(drafts)==1,drafts
  assert not page.evaluate('document.documentElement.scrollWidth>innerWidth')
  print('PASS hierarchy, typed area, details, actual JPEG compression/upload, partial failure retry without duplicate draft, supervisor own workspace, publication',width,mode,flush=True)
  context.close()
 browser.close()
