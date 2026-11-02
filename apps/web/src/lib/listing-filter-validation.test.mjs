import { test } from 'node:test';
import assert from 'node:assert/strict';
import { priceFilterError } from './listing-filter-validation.ts';

test('unselected and individual price bounds remain independent', () => {
  for (const [min, max] of [['', ''], ['100', ''], ['', '100'], ['0', '0'], ['100', '100']]) {
    assert.equal(priceFilterError(min, max), null);
  }
});

test('reversed bounds and invalid prices produce actionable feedback', () => {
  assert.match(priceFilterError('10000', '100'), /Maximum price/);
  for (const value of ['-1', 'Infinity', 'invalid']) assert.match(priceFilterError(value, ''), /valid price/);
  assert.equal(priceFilterError('100', '10000'), null);
});
