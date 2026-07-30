import 'package:flutter/material.dart';

import '../../../core/widgets/app_scope.dart';
import '../../shared/presentation/manage_workspace_scaffold.dart';
import '../../shared/presentation/notifications_screen.dart';
import '../../shared/presentation/profile_screen.dart';
import 'admin_bookings_tab.dart';
import 'categories_tab.dart';
import 'admin_dashboard_tab.dart';
import 'agent_verification_tab.dart';
import 'listing_approval_tab.dart';
import 'locations_tab.dart';
import 'promotions_tab.dart';
import 'reports_tab.dart';
import 'users_tab.dart';
import 'admin_growth_operations_screen.dart';

class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _currentIndex = 0;
  Set<String>? _permissions;
  bool _loadingPermissions = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_permissions != null || _loadingPermissions) return;
    _loadingPermissions = true;
    AppScope.of(context).repository.fetchMyAdminPermissions().then((value) {
      if (mounted) setState(() => _permissions = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Set<String>? permissions = _permissions;
    if (permissions == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final bool all = permissions.contains('*');
    bool allowed(String permission) => all || permissions.contains(permission);
    final List<ManageWorkspaceDestination> destinations =
        <ManageWorkspaceDestination>[
          const ManageWorkspaceDestination(
            label: "Dashboard",
            icon: Icons.dashboard_outlined,
            screen: AdminDashboardTab(),
          ),
          const ManageWorkspaceDestination(
            label: "Agents",
            icon: Icons.verified_user_outlined,
            screen: AgentVerificationTab(),
          ),
          const ManageWorkspaceDestination(
            label: "Users",
            icon: Icons.people_outline_rounded,
            screen: UsersTab(),
          ),
          const ManageWorkspaceDestination(
            label: "Listings",
            icon: Icons.rule_folder_outlined,
            screen: ListingApprovalTab(),
          ),
          const ManageWorkspaceDestination(
            label: "Categories",
            icon: Icons.category_outlined,
            screen: CategoriesTab(),
          ),
          const ManageWorkspaceDestination(
            label: "Locations",
            icon: Icons.place_outlined,
            screen: LocationsTab(),
          ),
          const ManageWorkspaceDestination(
            label: "Requests",
            icon: Icons.calendar_month_outlined,
            screen: AdminBookingsTab(),
          ),
          const ManageWorkspaceDestination(
            label: "Reports",
            icon: Icons.report_outlined,
            screen: ReportsTab(),
          ),
          const ManageWorkspaceDestination(
            label: "Promotions",
            icon: Icons.campaign_outlined,
            screen: PromotionsTab(),
          ),
          const ManageWorkspaceDestination(
            label: "Growth Ops",
            icon: Icons.monitor_heart_outlined,
            screen: AdminGrowthOperationsScreen(),
          ),
          const ManageWorkspaceDestination(
            label: "Notifications",
            icon: Icons.notifications_outlined,
            screen: NotificationsScreen(),
          ),
          const ManageWorkspaceDestination(
            label: "Profile",
            icon: Icons.person_outline,
            screen: ProfileScreen(),
          ),
        ];
    destinations.removeWhere(
      (destination) => switch (destination.label) {
        'Dashboard' => !allowed('dashboard.view'),
        'Agents' => !allowed('agents.manage'),
        'Users' => !allowed('users.view'),
        'Listings' => !allowed('listings.manage'),
        'Categories' =>
          !(allowed('listings.manage') || allowed('promotions.manage')),
        'Locations' => !(allowed('health.view') || allowed('agents.manage')),
        'Requests' => !allowed('bookings.manage'),
        'Reports' => !allowed('reports.manage'),
        'Promotions' => !allowed('promotions.manage'),
        'Growth Ops' =>
          !(allowed('analytics.view') ||
              allowed('payments.manage') ||
              allowed('risk.manage') ||
              allowed('boosts.manage')),
        'Notifications' =>
          !(allowed('support.manage') || allowed('health.view')),
        _ => false,
      },
    );
    if (_currentIndex >= destinations.length) _currentIndex = 0;
    return ManageWorkspaceScaffold(
      title: destinations[_currentIndex].label,
      currentIndex: _currentIndex,
      onSelect: (int index) => setState(() => _currentIndex = index),
      destinations: destinations,
    );
  }
}
