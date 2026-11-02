import { test } from 'node:test';
import assert from 'node:assert/strict';
import { registrationFetch } from './supabase-browser.ts';
import { agentRegistrationError } from './agent-registration-error.ts';

test('registration aborts a stalled request and gives an honest retry message', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = (_url, init) => new Promise((_, reject) => {
    init.signal.addEventListener('abort', () => reject(new DOMException('Request aborted', 'AbortError')), { once: true });
  });
  try {
    await assert.rejects(registrationFetch('https://fixture.invalid', {}, 5), (error) => {
      assert.match(agentRegistrationError(error), /could not confirm your registration in time/);
      return true;
    });
  } finally { globalThis.fetch = original; }
});
