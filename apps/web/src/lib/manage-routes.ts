export const manageSections = ['events-provider', 'events-coordinator', 'dashboard', 'information', 'business', 'admin-access', 'users', 'listings', 'add-listing', 'requests', 'categories', 'agents', 'owners', 'locations', 'reports', 'promotions', 'notifications', 'profile'] as const;
export type ManageSection = typeof manageSections[number];

export function manageHref(section: ManageSection, role?: 'admin' | 'agent') {
  const path = section === 'dashboard' ? '/manage' : `/manage/${section}`;
  return role ? `${path}?workspace=${role}` : path;
}

export function isManageSection(value: string): value is ManageSection {
  return (manageSections as readonly string[]).includes(value);
}
