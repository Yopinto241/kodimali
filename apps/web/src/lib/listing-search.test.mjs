import { test } from 'node:test';
import assert from 'node:assert/strict';
import { optionalNumber } from './listing-search.ts';

test('unselected and invalid price bounds do not filter listings', () => {
  for (const value of [undefined, '', '  ', 'invalid', 'Infinity', ['100'], '-1']) {
    assert.equal(optionalNumber(value, true), undefined);
  }
});

test('each selected price bound works independently, including zero', () => {
  assert.equal(optionalNumber('250000', true), 250000);
  assert.equal(optionalNumber('', true), undefined);
  assert.equal(optionalNumber('0', true), 0);
});

test('empty coordinates stay unset while valid signed coordinates survive', () => {
  assert.equal(optionalNumber(''), undefined);
  assert.equal(optionalNumber('-6.8'), -6.8);
});
