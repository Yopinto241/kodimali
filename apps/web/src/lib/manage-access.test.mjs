import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canUseManageTab, hasPermission } from './manage-access.ts';

test('each staff role sees its assigned workspace sections', () => {
  const roles = [
    [['dashboard.view', 'bookings.manage', 'health.view'], ['dashboard', 'requests', 'locations']],
    [['payments.manage', 'refunds.manage', 'wallets.manage', 'subscriptions.manage'], ['business']],
    [['information.manage', 'inventory.manage', 'referrals.manage', 'disputes.manage'], ['information', 'owners']],
    [['agents.manage', 'agent_roles.manage', 'agent_performance.view'], ['agents', 'locations']],
    [['events.manage', 'events.quotes', 'events.escalations', 'bookings.manage'], ['requests']],
    [['listings.manage', 'reports.manage', 'risk.manage'], ['business', 'listings', 'categories', 'reports']],
    [['promotions.manage', 'boosts.manage', 'analytics.view'], ['business', 'categories', 'promotions']],
    [['users.view', 'bookings.manage', 'support.manage'], ['requests', 'users']],
    [['dashboard.view', 'analytics.view', 'payments.view'], ['dashboard', 'business']],
  ];
  const sections = ['information', 'dashboard', 'business', 'admin-access', 'listings', 'requests', 'categories', 'agents', 'owners', 'users', 'locations', 'reports', 'promotions'];
  for (const [permissions, expected] of roles) {
    assert.deepEqual(sections.filter((tab) => canUseManageTab('admin', permissions, tab)), expected);
  }
  assert.ok(sections.every((tab) => canUseManageTab('admin', ['*'], tab)));
});

test('agent and unassigned admin cannot enter staff sections', () => {
  assert.equal(canUseManageTab('agent', [], 'admin-access'), false);
  assert.equal(canUseManageTab('agent', [], 'owners'), false);
  assert.equal(canUseManageTab('admin', [], 'business'), false);
  assert.equal(canUseManageTab('admin', [], 'profile'), true);
  assert.equal(canUseManageTab('admin', ['analytics.view'], 'unknown'), false);
});

test('supervisor can supervise agents without finance, users or role assignment', () => {
  const permissions = ['agents.manage', 'supervisor.scoped'];
  assert.equal(canUseManageTab('admin', permissions, 'agents'), true);
  for (const tab of ['business', 'admin-access', 'users', 'listings', 'requests', 'locations']) {
    assert.equal(canUseManageTab('admin', permissions, tab), false);
  }
});

test('analyst and marketing permissions grant no payment or role mutations', () => {
  for (const permissions of [['payments.view', 'analytics.view'], ['boosts.manage', 'analytics.view']]) {
    assert.equal(hasPermission(permissions, 'payments.manage'), false);
    assert.equal(hasPermission(permissions, '*'), false);
  }
});
