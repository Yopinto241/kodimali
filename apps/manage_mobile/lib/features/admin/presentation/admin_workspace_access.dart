class AdminWorkspaceAccess {
  const AdminWorkspaceAccess(this.permissions);

  final Set<String> permissions;

  bool allows(String permission) =>
      permissions.contains('*') || permissions.contains(permission);

  bool get roles => permissions.contains('*');
  bool get scopedSupervisor =>
      !roles && permissions.contains('supervisor.scoped');
  // Authorization must never depend on a translated display label.
  bool allowsDestination(String id) => scopedSupervisor
      ? const {'agents', 'notifications', 'profile'}.contains(id)
      : switch (id) {
          'dashboard' => allows('dashboard.view'),
          'information' => allows('information.manage'),
          'events' => allows('events.manage'),
          'agents' || 'agent-recommendations' => allows('agents.manage'),
          'contributor-rewards' => allows('payments.manage'),
          'users' => allows('users.view'),
          'listings' => allows('listings.manage'),
          'categories' =>
            allows('listings.manage') || allows('promotions.manage'),
          'locations' => allows('health.view') || allows('agents.manage'),
          'requests' => allows('bookings.manage'),
          'reports' => allows('reports.manage'),
          'promotions' => allows('promotions.manage'),
          'growth' => growth,
          'notifications' || 'profile' => true,
          _ => false,
        };
  bool get analytics => allows('analytics.view');
  bool get risks => allows('risk.manage');
  bool get refunds => allows('refunds.manage');
  bool get boosts => allows('boosts.manage');
  bool get payments => allows('payments.manage');
  bool get wallets => allows('wallets.manage');
  bool get financialReports => payments || refunds || allows('payments.view');
  bool get growth =>
      roles ||
      analytics ||
      risks ||
      refunds ||
      boosts ||
      payments ||
      wallets ||
      financialReports;
}
