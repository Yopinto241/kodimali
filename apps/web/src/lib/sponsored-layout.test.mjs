import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sponsoredLayout } from './sponsored-layout.ts';

test('large inventories keep organic space and every unique campaign', () => {
  const ads = Array.from({ length: 109 }, (_, index) => ({ promotion_id: `ad-${index}` }));
  const result = sponsoredLayout([...ads, ads[0]], 31);
  assert.equal(result.inline.length, 10);
  assert.equal(result.remaining.length, 99);
  assert.deepEqual([...result.inline, ...result.remaining], ads);
});

test('short and empty feeds put campaigns in the separate row, never ahead of listings', () => {
  const ads = [{ promotion_id: 'a' }, { promotion_id: 'b' }];
  for (const count of [0, 1, 2, 3]) {
    assert.deepEqual(sponsoredLayout(ads, count), { inline: [], remaining: ads });
  }
  assert.deepEqual(sponsoredLayout(ads, 4), { inline: [ads[0]], remaining: [ads[1]] });
  assert.deepEqual(sponsoredLayout([], 100), { inline: [], remaining: [] });
});
