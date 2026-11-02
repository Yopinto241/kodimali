import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pageMetadata, catalogMetadata, serviceSchema, breadcrumbs } from './seo.ts';
import { buildPublicSitemap, inventoryPath, staticPaths } from './sitemap.ts';

test('public metadata consistently uses the official domain and a single brand suffix', () => {
  const m = pageMetadata('Nyumba', 'Real description', '/listing/123');
  assert.equal(m.alternates.canonical, 'https://kodimali.com/listing/123');
  assert.equal(m.title.absolute, 'Nyumba | KODIMALI');
  assert.equal(m.openGraph.url, m.alternates.canonical);
  assert.equal(m.twitter.card, 'summary_large_image');
  assert.equal(pageMetadata('KODIMALI | Tanzania', 'Description', '/').title.absolute, 'KODIMALI | Tanzania');
});
test('arbitrary filters are noindex; real pagination self-canonicalizes; tracking does not create duplicates', () => {
  for (const query of [{ q: 'home' }, { minPrice: '0' }, { category: 'house' }, { lat: '-3' }, { regionId: 'x', page: '2' }, { page: '-1' }, { page: ['1','2'] }]) {
    const m = catalogMetadata('Mali', 'Description', '/listings', query);
    assert.equal(m.robots.index, false, JSON.stringify(query));
    assert.equal(m.alternates.canonical, 'https://kodimali.com/listings');
  }
  assert.equal(catalogMetadata('Mali', 'Description', '/listings', { page: '2' }).alternates.canonical, 'https://kodimali.com/listings?page=2');
  assert.equal(catalogMetadata('Mali', 'Description', '/listings', { utm_source: 'test' }).robots.index, true);
});
test('schema omits unproven availability, ratings and prices, retaining genuine zero prices', () => {
  const schema = serviceSchema({ title: 'Rental', path: '/listing/test', price: null });
  assert.equal(schema.offers, undefined);
  for (const price of [-1, 'not a price', Infinity]) assert.equal(serviceSchema({ title: 'Rental', path: '/listing/test', price }).offers, undefined);
  const priced = serviceSchema({ title: 'Rental', path: '/listing/test', price: 0, period: 'day' });
  assert.equal(priced.offers.priceSpecification.price, 0);
  assert.equal(priced.offers.priceSpecification.unitText, 'day');
  assert.ok(!JSON.stringify(priced).match(/InStock|rating|address|telephone/));
  assert.equal(breadcrumbs([['Home','/'],['Events','/events']]).itemListElement[1].position, 2);
});
test('existing flat sitemap includes all approved pages and real dates without private routes or invented dates', async () => {
  const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
  const calls=[];
  const result = await buildPublicSitemap([{slug:'house'}, {slug:'events'}], async (kind,page) => {
    calls.push([kind,page]);
    return kind === 'listings' ? { total_count:1005, entries:Array.from({length:page===0?1000:5},(_,i)=>({id:id(page*1000+i),updated_at:'2026-10-20T10:00:00Z'})) } : {total_count:0,entries:[]};
  });
  assert.ok(calls.some(([kind,page])=>kind==='listings'&&page===1));
  assert.equal(result.filter(row=>row.url.includes('/listing/')).length,1005);
  assert.ok(result.some(row=>row.url==='https://kodimali.com/events'));
  assert.ok(result.some(row=>row.url==='https://kodimali.com/toa-taarifa'));
  assert.ok(!result.some(row=>row.url.includes('/category/events')));
  assert.ok(!result.some(row=>/\/(account|admin|manage)(\/|$)/.test(row.url)));
  assert.equal(result.find(row=>row.url.includes('/listing/')).lastModified,'2026-10-20T10:00:00Z');
  assert.equal(result.find(row=>row.url==='https://kodimali.com/').lastModified,undefined);
  assert.equal(inventoryPath('services',id(1)),`/events/service/${id(1)}`);
  assert.throws(()=>inventoryPath('listings','../private'));
  await assert.rejects(buildPublicSitemap([],async()=>({total_count:1,entries:[]})));
  await assert.rejects(buildPublicSitemap([],async()=>({total_count:1,entries:[{id:id(1),updated_at:'bad'}]})));
  assert.ok(!staticPaths.includes('/account')&&!staticPaths.includes('/manage'));
});
