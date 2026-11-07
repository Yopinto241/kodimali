"""Browser + real local PostgreSQL checks with a test-only Supabase transport.

Start the built Next website on http://127.0.0.1:3317. Set the same guarded local
KODIMALI_LODGE_TEST_DSN used by test-lodges-postgres.py. No production writes.
"""
import base64
import datetime as dt
import json
import os
from pathlib import Path
import re
import time
from urllib.parse import urlparse
import psycopg
from psycopg import sql
from psycopg.types.json import Jsonb
from playwright.sync_api import sync_playwright, expect

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'tmp/lodges-20261107'
FIXTURE=json.loads((OUT/'browser-fixture.json').read_text(encoding='utf8'))
DSN=os.environ['KODIMALI_LODGE_TEST_DSN']
from psycopg.conninfo import conninfo_to_dict
assert conninfo_to_dict(DSN).get('host') in ('127.0.0.1','localhost')
assert conninfo_to_dict(DSN).get('dbname','').startswith('kodimali_lodges_')
BASE='http://127.0.0.1:3317'
RPCS={'lodge_workspace','lodge_register','lodge_command','lodge_enquire','lodge_my_requests','public_lodges','suggest_marketplace_locations'}
CALLS=[]


def rpc(name,body,actor):
    assert name in RPCS
    with psycopg.connect(DSN) as conn:
        conn.execute("select set_config('request.jwt.claim.sub',%s,true)",(actor or '',))
        conn.execute('set local role '+('authenticated' if actor else 'anon'))
        args=sql.SQL(',').join(sql.SQL('{}=>%s').format(sql.Identifier(k)) for k in body)
        query=sql.SQL('select public.{}({})').format(sql.Identifier(name),args)
        return conn.execute(query,[Jsonb(v) if isinstance(v,(dict,list)) else v for v in body.values()]).fetchone()[0]


def user(uid):
    return {'id':uid,'aud':'authenticated','role':'authenticated','email':uid+'@example.invalid','email_confirmed_at':'2026-01-01T00:00:00Z','app_metadata':{'provider':'email'},'user_metadata':{'full_name':'Local test user'},'created_at':'2026-01-01T00:00:00Z'}


def context(browser,width,actor=None):
    c=browser.new_context(viewport={'width':width,'height':900},device_scale_factor=1)
    c.add_cookies([{'name':'kodimali_language','value':'en','url':BASE}])
    init="localStorage.setItem('kodimali_language','en');localStorage.setItem('kodimali_browser_device_id','lodge-test');localStorage.setItem('kodimali_welcome_seen_v1','lodge-test');"
    if actor:
        enc=lambda v:base64.urlsafe_b64encode(json.dumps(v).encode()).decode().rstrip('=')
        token=enc({'alg':'HS256','typ':'JWT'})+'.'+enc({'sub':actor,'role':'authenticated','aud':'authenticated','exp':int(time.time())+3600})+'.fixture-not-a-production-signature'
        session={'access_token':token,'refresh_token':'fixture-only','expires_at':int(time.time())+3600,'expires_in':3600,'token_type':'bearer','user':user(actor)}
        init+="localStorage.setItem('sb-tlhoajedyaeaaqtrjqqh-auth-token',"+json.dumps(json.dumps(session))+");"
    c.add_init_script(init)
    def transport(route):
        request=route.request;path=urlparse(request.url).path
        if request.method=='OPTIONS':return route.fulfill(status=200,headers={'access-control-allow-origin':'*','access-control-allow-headers':'*'},body='')
        if '/auth/v1/user' in path:return route.fulfill(json=user(actor),headers={'access-control-allow-origin':'*'})
        if '/rest/v1/rpc/' in path:
            name=path.rsplit('/',1)[1]
            if name not in RPCS:return route.fulfill(status=403,json={'message':'Unexpected test RPC denied'})
            body=request.post_data_json or {};CALLS.append({'rpc':name,'action':body.get('p_action')})
            try:return route.fulfill(body=json.dumps(rpc(name,body,actor),default=str),content_type='application/json',headers={'access-control-allow-origin':'*'})
            except psycopg.Error as error:return route.fulfill(status=400,json={'code':error.sqlstate,'message':error.diag.message_primary},headers={'access-control-allow-origin':'*'})
        if path.endswith('/rest/v1/locations'):
            # The production location selector uses these narrow read-only queries.
            from urllib.parse import parse_qs
            q=parse_qs(urlparse(request.url).query)
            clauses=['is_active'];values=[]
            for column in ['id','parent_id','location_type']:
                value=q.get(column,[''])[0]
                if value.startswith('eq.'):
                    clauses.append(column+'=%s');values.append(value[3:])
            with psycopg.connect(DSN) as conn:
                result=conn.execute('select id::text,name,location_type::text,parent_id::text from public.locations where '+' and '.join(clauses)+' limit 100',values).fetchall()
            data=[dict(zip(['id','name','location_type','parent_id'],row)) for row in result]
            if 'application/vnd.pgrst.object+json' in request.headers.get('accept',''):data=data[0] if data else None
            return route.fulfill(json=data,headers={'access-control-allow-origin':'*'})
        # Block every other browser request to Supabase, including payments.
        return route.fulfill(status=403,json={'message':'Not part of the isolated lodge transport'},headers={'access-control-allow-origin':'*'})
    c.route('https://tlhoajedyaeaaqtrjqqh.supabase.co/**',transport)
    return c


def main():
    results=[]
    with sync_playwright() as p:
        browser=p.chromium.launch(headless=True)
        for width in [390,1440]:
            c=context(browser,width,FIXTURE['owner']);page=c.new_page();errors=[];page.on('pageerror',lambda error:errors.append(str(error)))
            page.goto(BASE+'/manage/lodges',wait_until='domcontentloaded',timeout=90000)
            expect(page.get_by_text('Local Lodge Test',exact=True)).to_be_visible(timeout=45000)
            page.get_by_text('Local Lodge Test',exact=True).click()
            expect(page.get_by_role('link',name='Rooms',exact=True)).to_be_visible(timeout=30000)
            page.get_by_role('link',name='Room types',exact=True).click()
            page.get_by_role('button',name='Add room type',exact=True).click()
            form=page.get_by_role('dialog')
            form.get_by_label('Room type name',exact=True).fill('Deluxe-'+str(width))
            form.get_by_label('Description',exact=True).fill('Owner-configured room facilities')
            form.get_by_label('Bed configuration',exact=True).fill('Double bed')
            form.get_by_label('Price per night',exact=True).fill('25000')
            form.get_by_role('button',name='Save',exact=True).click()
            expect(form).not_to_be_visible(timeout=30000)
            page.get_by_role('link',name='Rooms',exact=True).click()
            expect(page.get_by_role('button',name='Add room',exact=True)).to_be_visible(timeout=30000)
            page.get_by_role('button',name='Add room',exact=True).click()
            form=page.get_by_role('dialog');form.get_by_label('Room number or name',exact=True).fill('UI-'+str(width)+'-'+str(int(time.time())))
            expect(form.locator('select[name=room_type_id]').locator('option').first).to_be_attached(timeout=30000)
            type_options=form.locator('select[name=room_type_id]').locator('option').evaluate_all('(nodes)=>nodes.map(n=>({value:n.value,text:n.textContent}))')
            form.locator('select[name=room_type_id]').select_option(next(x['value'] for x in type_options if x['text'].startswith('Deluxe-'+str(width))))
            form.get_by_role('button',name='Save',exact=True).click()
            expect(form).not_to_be_visible(timeout=30000)
            page.get_by_role('link',name='Calendar',exact=True).click()
            expect(page.get_by_role('table')).to_be_visible(timeout=30000)
            page.get_by_label('Room type',exact=True).fill('Deluxe')
            page.get_by_role('button',name='Search',exact=True).click()
            expect(page.get_by_role('cell',name='Deluxe-'+str(width),exact=True).first).to_be_visible(timeout=30000)
            page.get_by_role('link',name='Reservations',exact=True).click()
            expect(page.get_by_role('button',name='New reservation',exact=True).first).to_be_visible(timeout=30000)
            page.get_by_role('button',name='New reservation',exact=True).first.click()
            form=page.get_by_role('dialog')
            expect(form.locator('select[name=room_ids]').locator('option').first).to_be_attached(timeout=30000)
            options=form.locator('select[name=room_ids]').locator('option').evaluate_all('(nodes)=>nodes.map(n=>({value:n.value,text:n.textContent}))')
            room=next(x['value'] for x in options if 'UI-'+str(width) in x['text'])
            form.locator('select[name=room_ids]').select_option([room])
            today=dt.datetime.now(dt.timezone.utc).date();form.get_by_label('Arrival',exact=True).fill(today.isoformat());form.get_by_label('Departure',exact=True).fill((today+dt.timedelta(days=1)).isoformat())
            form.get_by_label('Guest name',exact=True).fill('UI Guest '+str(width))
            form.locator('select[name=channel]').select_option('phone' if width==1440 else 'walk_in')
            form.get_by_role('button',name='Save',exact=True).click();expect(form).not_to_be_visible(timeout=30000)
            card=page.locator('article').filter(has=page.get_by_role('heading',name=re.compile('UI Guest '+str(width))))
            card.get_by_role('button',name='Check in',exact=True).click();expect(card.get_by_role('button',name='Check out',exact=True)).to_be_visible(timeout=30000)
            card.get_by_role('button',name='Record lodge payment',exact=True).click();form=page.get_by_role('dialog')
            form.get_by_label('Amount collected',exact=True).fill('5000');form.get_by_label('Payment method description',exact=True).fill('Cash')
            form.get_by_role('button',name='Save',exact=True).click();expect(form).not_to_be_visible(timeout=30000)
            expect(card.get_by_text(re.compile('Outstanding balance.*20000'))).to_be_visible(timeout=30000)
            card.get_by_role('button',name='Check out',exact=True).click()
            expect(card.get_by_text(re.compile('checked out'))).to_be_visible(timeout=30000)
            expect(page.locator('.navigation-progress')).not_to_be_visible(timeout=30000)
            page.screenshot(path=str(OUT/f'workspace-{width}.png'),full_page=False)
            assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'), 'Management page overflows viewport'
            page.goto(BASE+'/lodges/'+FIXTURE['lodge'],wait_until='domcontentloaded')
            expect(page.get_by_role('heading',name='Local Lodge Test',exact=True).first).to_be_visible(timeout=30000)
            expect(page.locator('.navigation-progress-inline')).not_to_be_visible(timeout=30000)
            assert not page.get_by_text('UI Guest '+str(width),exact=True).count(),'Public guest leak'
            page.screenshot(path=str(OUT/f'public-{width}.png'),full_page=False)
            request_date=today+dt.timedelta(days=90)
            request_form=page.locator('form').filter(has=page.locator('select[name=room_type_id]'))
            options=request_form.locator('select[name=room_type_id] option').evaluate_all('(nodes)=>nodes.map(n=>({value:n.value,text:n.textContent}))')
            request_form.locator('select[name=room_type_id]').select_option(next(x['value'] for x in options if x['text'].startswith('Deluxe-'+str(width))))
            request_form.locator('input[name=arrival]').fill(request_date.isoformat())
            request_form.locator('input[name=departure]').fill((request_date+dt.timedelta(days=1)).isoformat())
            request_form.locator('input[name=contact_phone]').fill('255700123456')
            request_form.locator('input[name=message]').fill('Isolated marketplace request '+str(width))
            request_form.get_by_role('button',name='Send enquiry',exact=True).click()
            expect(page.get_by_text('Awaiting lodge confirmation',exact=False).first).to_be_visible(timeout=30000)
            page.goto(BASE+f"/manage/lodges/{FIXTURE['lodge']}/reservations",wait_until='domcontentloaded')
            request_card=page.locator('article').filter(has=page.get_by_text('Isolated marketplace request '+str(width),exact=True))
            request_card.get_by_role('button',name='Confirm and allocate room',exact=True).click()
            expect(request_card.get_by_role('button',name='Confirm and allocate room',exact=True)).not_to_be_visible(timeout=30000)
            expect(page.locator('.navigation-progress')).not_to_be_visible(timeout=30000)
            page.goto(BASE+'/lodges/'+FIXTURE['lodge'],wait_until='domcontentloaded')
            expect(page.get_by_text(re.compile('Reservation confirmed / confirmed')).first).to_be_visible(timeout=30000)
            results.append({'viewport':width,'room_creation':True,'room_type_calendar':True,'reservation_channel':'phone' if width==1440 else 'walk_in','marketplace_request_and_atomic_confirmation':True,'check_in_out':True,'direct_payment':True,'no_horizontal_overflow':True,'public_guest_isolation':True,'page_errors':errors})
            c.close()
        c=context(browser,390,FIXTURE['other']);page=c.new_page();page.goto(BASE+f"/manage/lodges/{FIXTURE['lodge']}/guests",wait_until='domcontentloaded')
        expect(page.get_by_role('alert')).to_be_visible(timeout=30000)
        assert not page.get_by_text('UI Guest 390',exact=True).count()
        c.close();browser.close()
    assert not any(x['page_errors'] for x in results),results
    assert all(not x['rpc'].startswith(('create_payment','sonic','clickpesa')) for x in CALLS)
    (OUT/'browser-results.json').write_text(json.dumps({'checks':results,'cross_lodge_denied':True,'provider_calls':0},indent=2),encoding='utf8')
    print(json.dumps({'checks':results,'cross_lodge_denied':True,'provider_calls':0}))


if __name__=='__main__':main()
