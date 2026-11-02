import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
const require = createRequire(import.meta.url);
const ts = require('typescript');
const source = readFileSync(new URL('./ui-translation.ts', import.meta.url), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, esModuleInterop: true, target: ts.ScriptTarget.ES2022 } }).outputText;
const exports = {};
new Function('require','exports', compiled)(require,exports);
const { translateUiText: tr } = exports;
const copy = require('./ui-copy.json');
const aliases = require('./ui-aliases.json');

test('application copy switches in both directions including previous Swahili-only screens', () => {
  assert.equal(tr('sw','Save changes'),'Hifadhi mabadiliko');
  assert.equal(tr('en','Hifadhi mabadiliko'),'Save changes');
  assert.equal(tr('en','Taarifa Zangu'),'My Information');
  assert.equal(tr('sw','Owner name'),'Jina la mmiliki');
  assert.equal(tr('sw','Bedrooms *'),'Vyumba vya kulala *');
  assert.equal(tr('en','Vyumba vya kulala *'),'Bedrooms *');
  assert.equal(tr('sw','acre'),'ekari');
  assert.equal(tr('en','Makubaliano ya mwisho · Version'),'Final agreement · Version');
  assert.equal(tr('sw','Lipa deposit'),'Lipa amana');
  assert.equal(tr('en','Booking imethibitishwa bila malipo kwa sababu admin amewasha free booking.'),'Booking confirmed without payment because an administrator enabled free booking.');
});
test('apartment, book and booking remain unchanged and customer content is untouched', () => {
  for (const language of ['sw','en']) for (const term of ['apartment','Apartment','book','Book','booking','Booking']) assert.equal(tr(language,term),term);
  for (const text of ['My apartment near Njiro, owned by Amina','Nyumba nzuri ya Amina','255712345678','financekodimali@kodimali.com','REF-001','Amina Said']) {
    assert.equal(tr('en',text),text);assert.equal(tr('sw',text),text);
  }
  for(const [en,sw] of Object.entries(copy)) for(const term of ['apartment','book','booking']) {
    if(new RegExp(`\\b${term}s?\\b`,'i').test(en)) assert.ok(new RegExp(`\\b${term}s?\\b`,'i').test(sw),`${en} => ${sw}`);
  }
});
test('templates preserve reference values, prices and destructive-confirmation tokens', () => {
  assert.equal(tr('en','Ombi limetumwa. Namba: EVT-123'),'Request sent. Reference: EVT-123');
  assert.equal(tr('sw','Pay deposit — TZS 10,000'),'Lipa amana — TZS 10,000');
  assert.equal(tr('en','Tafuta Nyumba'),'Search House');
  const text=tr('sw','Permanently delete “Amina apartment”? This removes its media and related activity and cannot be undone. Type DELETE to continue.');
  assert.ok(text.includes('Amina apartment'));assert.ok(text.includes('DELETE'));
  assert.equal(tr('en','You may ask to correct or delete account information. See the ').endsWith(' '),true);
});
test('all statically wrapped copy has a translation or an intentional invariant', () => {
  const known = new Set([...Object.keys(copy),...Object.values(copy),...Object.keys(aliases)]);
  const missing=[];
  function scan(dir){for(const entry of readdirSync(dir,{withFileTypes:true})){
    const file=join(dir,entry.name);if(entry.isDirectory()){scan(file);continue;}if(!file.endsWith('.tsx'))continue;
    const ast=ts.createSourceFile(file,readFileSync(file,'utf8'),99,true,4);
    function walk(node){if(ts.isJsxSelfClosingElement(node)&&node.tagName.getText(ast)==='UiText'){
      const attr=node.attributes.properties.find(p=>ts.isJsxAttribute(p)&&p.name.text==='text');const value=attr?.initializer?.expression;
      if(value&&ts.isStringLiteral(value)&&!known.has(value.text.trim())&&/[a-z]{2}/i.test(value.text))missing.push(`${file}: ${value.text}`);
    }ts.forEachChild(node,walk);}walk(ast);
  }}
  scan(new URL('../',import.meta.url).pathname.replace(/^\/(\w:)/,'$1'));
  assert.deepEqual(missing,[]);
});
