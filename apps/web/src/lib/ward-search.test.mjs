import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyWardLocation, wardLocation } from './ward-search.ts';

test('GPS searches a whole ward and preserves independent price/category filters', () => {
  const url = new URL('https://kodimali.com/category/house?minPrice=100&sort=price_low&areaId=old&lat=-6&lng=39&page=3');
  applyWardLocation(url, { region_id: 'r', district_id: 'd', ward_id: 'w' });
  assert.equal(url.pathname, '/category/house');
  assert.equal(url.searchParams.get('wardId'), 'w');
  for (const key of ['lat', 'lng', 'areaId', 'page']) assert.equal(url.searchParams.has(key), false);
  assert.equal(url.searchParams.get('minPrice'), '100');
  assert.equal(url.searchParams.get('sort'), 'price_low');
});

test('GPS requires a resolved ward and never silently substitutes a region or area', () => {
  for (const value of [null, {}, { region_id: 'r' }, { region_id: 'r', district_id: 'd', area_id: 'a' }]) assert.equal(wardLocation(value), null);
  assert.equal(wardLocation({ region_id: 'r', district_id: 'd', ward_id: 'w', area_id: 'a' }).ward_id, 'w');
});
