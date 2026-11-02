import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
const require=createRequire(import.meta.url), ts=require('typescript');
function load(file, dependencies={}) {
  const code=ts.transpileModule(readFileSync(new URL(file,import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
  const exports={};new Function('require','exports',code)((name)=>dependencies[name]??require(name),exports);return exports;
}
const {normalizeWhatsAppNumber:normal,whatsAppUrl}=load('./whatsapp.ts');
test('WhatsApp accepts formatted Tanzania and international numbers without malformed links',()=>{
  for(const phone of ['0712 345 678','712345678','+255 (712) 345-678','00255 712345678']) assert.equal(normal(phone),'255712345678');
  assert.equal(whatsAppUrl('+44 7700 900123'),'https://wa.me/447700900123');
  for(const phone of [null,'','abc0712345678','123','255712','000000000000','+2557123456789999']) assert.equal(whatsAppUrl(phone),null);
});
test('advertising failures and blocked storage cannot interrupt browsing; destinations are safe',async()=>{
  let calls=0;
  globalThis.window={get sessionStorage(){throw new Error('blocked');}};
  const {promotionSession,recordPromotion,promotionDestination:dest}=load('./promotion-tracking.ts',{'./supabase-browser':{getBrowserSupabase:()=>({rpc(){calls++;return Promise.reject(new Error('offline'));}})}});
  assert.equal(promotionSession(),promotionSession());
  assert.doesNotThrow(()=>recordPromotion('fixture','impression'));
  await new Promise(resolve=>setTimeout(resolve,0));assert.equal(calls,1);
  for(const value of [null,'','javascript:alert(1)','data:text/html,hi','https://user:secret@example.com']) assert.equal(dest(value),'/listings');
  assert.equal(dest('/events?category=chairs'),'/events?category=chairs');
  assert.equal(dest('https://kodimali.com/listings?q=viti'),'/listings?q=viti');
  assert.equal(dest('//example.com/ad'),'https://example.com/ad');
  delete globalThis.window;
});
