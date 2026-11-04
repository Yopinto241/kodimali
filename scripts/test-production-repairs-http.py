"""Exercise real PostgREST/RLS on the localhost metadata fixture, never Supabase."""
import base64, hashlib, hmac, json, os, subprocess, time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'tmp/repair-tests'
database = (OUT / 'database.txt').read_text().strip()
assert database.startswith('repair_fixture_20261104_')
secret = 'localhost-fixture-only-secret-at-least-thirty-two-bytes'
config = OUT / 'postgrest.conf'
config.write_text(f'db-uri = "postgres://postgres@127.0.0.1:55439/{database}"\ndb-schemas = "public"\ndb-anon-role = "anon"\njwt-secret = "{secret}"\nserver-host = "127.0.0.1"\nserver-port = 55440\n')
log = (OUT / 'postgrest.log').open('w')
process = subprocess.Popen([str(ROOT / 'tmp/repair-tools/postgrest.exe'), str(config)], stdout=log, stderr=log, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)

def token(actor=None, role='authenticated'):
    enc = lambda obj: base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip('=')
    claims = {'role':role,'exp':int(time.time())+300}
    if actor: claims['sub'] = str(__import__('uuid').UUID(hashlib.md5(('repair-'+actor).encode()).hexdigest()))
    raw = enc({'alg':'HS256','typ':'JWT'})+'.'+enc(claims)
    return raw+'.'+base64.urlsafe_b64encode(hmac.new(secret.encode(),raw.encode(),hashlib.sha256).digest()).decode().rstrip('=')

def request(path, actor=None, body=None, role='authenticated'):
    headers = {'Content-Type':'application/json'}
    if actor or role == 'service_role': headers['Authorization'] = 'Bearer '+token(actor,role)
    try:
        with urlopen(Request('http://127.0.0.1:55440/'+path,headers=headers,data=None if body is None else json.dumps(body).encode()),timeout=10) as response:
            raw=response.read(); return response.status,json.loads(raw) if raw else None
    except HTTPError as error: return error.code,json.loads(error.read())

try:
    for _ in range(100):
        try: request(''); break
        except URLError: time.sleep(.1)
    else: raise RuntimeError('Local PostgREST did not start')
    for actor,count in [('analyst',0),('marketing',0),('finance',0),('support',2),('customer',1),('agent',1),('owner',1),('supervisor',0),('superadmin',2)]:
        status,rows=request('booking_requests?select=id',actor)
        assert status==200 and len(rows)==count,(actor,status,rows)
        print('PASS: JWT/RLS booking scope '+actor)
    for actor in [None,'customer','analyst']:
        status,_=request('rpc/grant_listing_chat_access',actor,{'p_payment_id':str(__import__('uuid').UUID(hashlib.md5(b'repair-chat').hexdigest()))})
        assert status in (401,403,404),(actor,status)
        print('PASS: JWT denied entitlement grant '+str(actor))
    status,_=request('rpc/push_registration_has_active_session','analyst',{'p_device_id':'00000000-0000-0000-0000-000000000000'})
    assert status in (401,403,404)
    print('PASS: JWT denied internal session inspection')
    from concurrent.futures import ThreadPoolExecutor
    payment=str(__import__('uuid').UUID(hashlib.md5(b'repair-chat').hexdigest()))
    args={'p_table':'listing_chat_payments','p_payment_id':payment,'p_provider':'sonicpesa','p_status':'paid','p_transaction_id':'http-concurrent-fixture','p_payload':{'order_id':'sp_fixture_chat','amount':1000,'currency':'TZS'}}
    with ThreadPoolExecutor(max_workers=4) as pool:
        results=list(pool.map(lambda _:request('rpc/apply_verified_payment_event',body=args,role='service_role'),range(4)))
    assert all(status==200 and value['status']=='paid' for status,value in results),results
    status,rows=request('chat_entitlement_grants?select=payment_id&payment_id=eq.'+payment,role='service_role')
    assert status==200 and len(rows)==1,(status,rows)
    assert sum(not value.get('duplicate',False) for _,value in results)==1,results
    print('PASS: four concurrent verified callbacks produce one durable grant')
finally:
    process.terminate();process.wait(timeout=10);log.close()
