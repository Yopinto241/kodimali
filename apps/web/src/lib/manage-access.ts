export function hasPermission(permissions: readonly string[], permission: string) {
  return permissions.includes('*') || permissions.includes(permission);
}

export function canUseManageTab(role: 'admin' | 'agent', permissions: readonly string[], tab: string) {
  if (role === 'agent') return ['events-provider', 'dashboard', 'business', 'listings', 'add-listing', 'requests', 'notifications', 'profile'].includes(tab);
  if (permissions.includes('supervisor.scoped') && !permissions.includes('*') && !['agents', 'profile', 'notifications'].includes(tab)) return false;
  const required: Record<string, string[]> = {
    'events-coordinator': ['events.manage'],
    'events-provider': ['*'],
    dashboard: ['dashboard.view'],
    information: ['information.manage'],
    business: ['analytics.view', 'payments.manage', 'boosts.manage', 'risk.manage', 'refunds.manage'],
    'admin-access': ['*'],
    listings: ['listings.manage'], requests: ['bookings.manage'],
    categories: ['listings.manage', 'promotions.manage'], agents: ['agents.manage'],
    owners: ['inventory.manage'], users: ['users.view'],
    locations: ['health.view', 'agents.manage'], reports: ['reports.manage'],
    promotions: ['promotions.manage'],
  };
  if (tab === 'profile' || tab === 'notifications') return true;
  return (required[tab] ?? []).some((permission) => hasPermission(permissions, permission));
}
