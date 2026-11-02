"""Live preflight/session-denial checks; no account or listing is modified."""
import json,urllib.request,urllib.error
base='https://tlhoajedyaeaaqtrjqqh.supabase.co/functions/v1/'
for name in ['create-agent-listing-payment','check-agent-listing-payment']:
 req=urllib.request.Request(base+name,method='OPTIONS',headers={'Origin':'https://kodimali.com','Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'authorization,apikey,content-type,x-client-info'})
 with urllib.request.urlopen(req,timeout=30) as res:
  assert res.status in [200,204]
  assert res.headers.get('Access-Control-Allow-Origin')=='*'
 for headers in [{},{'Authorization':'Bearer invalid-session'}]:
  try:
   urllib.request.urlopen(urllib.request.Request(base+name,data=b'{}',headers={'Content-Type':'application/json',**headers}),timeout=30)
   raise AssertionError('Invalid session accepted')
  except urllib.error.HTTPError as e:
   body=json.load(e)
   assert e.code==401,(e.code,body)
   assert 'error' in body,body
   assert 'Sign in again' in body['error'],body
 print('PASS live preflight and handler-level rejection of missing/invalid sessions',name,flush=True)
