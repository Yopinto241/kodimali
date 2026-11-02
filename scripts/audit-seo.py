"""Read-only HTTP/HTML audit. Googlebot user-agent tests do not impersonate verified crawler IPs."""
import argparse,concurrent.futures,json,re,time,urllib.request,urllib.error,xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
class HTML(HTMLParser):
 def __init__(self):super().__init__();self.title='';self.meta={};self.canon=[];self.links=[];self.h1=[];self.schemas=[];self.lang=None;self.skip=0;self.in_title=False;self.in_h1=False;self.schema=None;self.images=[]
 def handle_starttag(self,tag,attrs):
  a=dict(attrs)
  if tag=='html':self.lang=a.get('lang')
  if tag=='title':self.in_title=True
  if tag=='h1':self.in_h1=True;self.h1.append('')
  if tag=='meta':self.meta[a.get('name') or a.get('property') or '']=a.get('content','')
  if tag=='link' and a.get('rel')=='canonical':self.canon.append(a.get('href'))
  if tag=='a' and a.get('href'):self.links.append(a['href'])
  if tag=='img':self.images.append({k:a.get(k) for k in ['src','alt','width','height','loading','fetchpriority']})
  if tag=='script':self.skip+=1;self.schema='' if a.get('type')=='application/ld+json' else None
 def handle_endtag(self,tag):
  if tag=='title':self.in_title=False
  if tag=='h1':self.in_h1=False
  if tag=='script':
   self.skip=max(0,self.skip-1)
   if self.schema is not None:
    try:self.schemas.append(json.loads(self.schema))
    except ValueError:self.schemas.append({'parse_error':True})
   self.schema=None
 def handle_data(self,data):
  if self.schema is not None:self.schema+=data
  if self.skip:return
  if self.in_title:self.title+=data
  if self.in_h1:self.h1[-1]+=data
AGENTS={'browser':'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36','googlebot':'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)','bingbot':'Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)'}
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):return None

def fetch(url,agent='browser',follow=True):
 start=time.monotonic()
 try:
  opener=urllib.request.build_opener() if follow else urllib.request.build_opener(NoRedirect())
  try:r=opener.open(urllib.request.Request(url,headers={'User-Agent':AGENTS[agent]}),timeout=45)
  except urllib.error.HTTPError as e:r=e
  raw=r.read().decode('utf-8','replace');headers={k.lower():v for k,v in r.headers.items()};p=HTML();p.feed(raw)
  result={'url':url,'final_url':r.url,'agent':agent,'status':r.status,'seconds':round(time.monotonic()-start,3),'headers':{k:headers[k] for k in ['content-type','x-robots-tag','location','cf-mitigated','cache-control','server'] if k in headers},'title':p.title,'description':p.meta.get('description'),'robots':p.meta.get('robots'),'googlebot':p.meta.get('googlebot'),'canonical':p.canon,'lang':p.lang,'h1':p.h1,'meta':p.meta,'schemas':p.schemas,'listing_links':sorted(set(x for x in p.links if re.match(r'/listing/[^/?#]+$',x))),'images':p.images[:8]}
  if '/robots.txt' in url or '/sitemap' in url:result['body']=raw
  return result
 except Exception as e:return {'url':url,'agent':agent,'error':str(e)}
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--base',default='https://kodimali.com');parser.add_argument('--out',default='tmp/seo-audit-before.json');args=parser.parse_args();base=args.base.rstrip('/')
 paths=['/','/listings','/category/house','/category/car','/category/no-such-category','/events','/events/plan','/toa-taarifa','/login','/account','/admin','/robots.txt','/sitemap.xml','/listing/00000000-0000-0000-0000-000000000000','/listings?minPrice=1000']
 with concurrent.futures.ThreadPoolExecutor(max_workers=5) as ex:results=list(ex.map(lambda path:fetch(base+path),paths))
 listings=next((x['listing_links'] for x in results if x.get('listing_links')),[])
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:results+=list(ex.map(lambda path:fetch(base+path),listings[:2]))
 results+=[fetch(base+path,agent) for agent in ['googlebot','bingbot'] for path in ['/','/robots.txt','/sitemap.xml']]
 if base.startswith('https://kodimali.com'):results+=[fetch(url,follow=False) for url in ['http://kodimali.com/events','https://www.kodimali.com/events','http://www.kodimali.com/events']]
 out=Path(args.out);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(results,indent=2,ensure_ascii=False),encoding='utf-8')
 for row in results:print(row.get('status','ERROR'),row['agent'],row['url'],'title:',row.get('title','')[:70].encode('ascii','backslashreplace').decode(),'canonical:',row.get('canonical'),flush=True)
