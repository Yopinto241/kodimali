import { test } from 'node:test';
import assert from 'node:assert/strict';
import { agentRegistrationError, registrationUnavailable } from './agent-registration-error.ts';

test('registration never exposes raw server, database or unknown errors', () => {
  for (const error of [
    { status: 500, message: 'Database error saving new user' },
    new Error('column reference id is ambiguous in public.agents'),
    { message: 'SQLSTATE 23505 secret_constraint' },
    new Error('Internal Server Error'),
    new Error('unexpected upstream implementation detail'),
    null,
  ]) assert.equal(agentRegistrationError(error), registrationUnavailable);
});
test('known validation problems provide actionable messages', () => {
  assert.match(agentRegistrationError({ code: 'user_already_exists' }), /sign in or reset your password/);
  assert.match(agentRegistrationError(new Error('Username is already in use')), /choose another username/);
  assert.match(agentRegistrationError({ code: 'weak_password' }), /stronger password/);
  assert.match(agentRegistrationError({ message: 'Agent location must be an active area' }), /ward and operating area/);
  assert.match(agentRegistrationError({ code: 'over_email_send_rate_limit' }), /wait a few minutes/);
});
