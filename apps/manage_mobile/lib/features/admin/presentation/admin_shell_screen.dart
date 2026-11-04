import 'package:flutter_core/localized_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

import '../../../core/widgets/app_scope.dart';
import '../../shared/presentation/manage_workspace_scaffold.dart';
import '../../shared/presentation/notifications_screen.dart';
import '../../shared/presentation/profile_screen.dart';
import 'admin_bookings_tab.dart';
import 'categories_tab.dart';
import 'admin_dashboard_tab.dart';
import 'referral_finance_screen.dart';
import '../../shared/presentation/agent_recommendations_screen.dart';
import 'admin_workspace_access.dart';
import '../../../core/utils/user_facing_error.dart';
import 'agent_verification_tab.dart';
import 'listing_approval_tab.dart';
import 'locations_tab.dart';
import 'promotions_tab.dart';
import 'reports_tab.dart';
import 'users_tab.dart';
import 'admin_growth_operations_screen.dart';
import 'information_administration_tab.dart';
import '../../events/presentation/event_coordinator_screen.dart';

class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _currentIndex = 0;
  Set<String>? _permissions;
  bool _loadingPermissions = false;
  String? _permissionError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_permissions != null || _loadingPermissions) return;
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    setState(() {
      _loadingPermissions = true;
      _permissionError = null;
    });
    try {
      final value = await AppScope.of(
        context,
      ).repository.fetchMyAdminPermissions();
      if (mounted) {
        setState(() {
          _permissions = value;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _permissionError = userFacingError(
            error,
            fallback: 'Could not load your workspace. Please try again.',
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingPermissions = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Set<String>? permissions = _permissions;
    if (_permissionError != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_permissionError!),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadPermissions,
                child: const LocalizedUiText('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (permissions == null) {
      return Scaffold(
        body: KodimaliLoading(label: mobileUi(context, 'Loading...')),
      );
    }
    final access = AdminWorkspaceAccess(permissions);
    final List<ManageWorkspaceDestination> destinations =
        <ManageWorkspaceDestination>[
          ManageWorkspaceDestination(
            id: 'dashboard',
            label: mobileUi(context, "Dashboard"),
            icon: Icons.dashboard_outlined,
            screen: AdminDashboardTab(access: access),
          ),
          ManageWorkspaceDestination(
            id: 'information',
            label: mobileUi(context, "Information Administration"),
            icon: Icons.fact_check_outlined,
            screen: InformationAdministrationTab(),
          ),
          ManageWorkspaceDestination(
            id: 'events',
            label: mobileUi(context, "Events Coordinator"),
            icon: Icons.celebration_outlined,
            screen: EventCoordinatorScreen(),
          ),
          ManageWorkspaceDestination(
            id: 'agents',
            label: mobileUi(context, "Agents"),
            icon: Icons.verified_user_outlined,
            screen: AgentVerificationTab(
              canAssignSupervisors: access.roles,
              scopedSupervisor: access.scopedSupervisor,
            ),
          ),
          ManageWorkspaceDestination(
            id: 'agent-recommendations',
            label: mobileUi(context, 'Agent recommendations'),
            icon: Icons.person_add_alt,
            screen: AgentRecommendationsScreen(admin: true),
          ),
          ManageWorkspaceDestination(
            id: 'contributor-rewards',
            label: mobileUi(context, 'Contributor rewards'),
            icon: Icons.redeem_outlined,
            screen: ReferralFinanceScreen(),
          ),
          ManageWorkspaceDestination(
            id: 'users',
            label: mobileUi(context, "Users"),
            icon: Icons.people_outline_rounded,
            screen: UsersTab(),
          ),
          ManageWorkspaceDestination(
            id: 'listings',
            label: mobileUi(context, "Listings"),
            icon: Icons.rule_folder_outlined,
            screen: ListingApprovalTab(),
          ),
          ManageWorkspaceDestination(
            id: 'categories',
            label: mobileUi(context, "Categories"),
            icon: Icons.category_outlined,
            screen: CategoriesTab(),
          ),
          ManageWorkspaceDestination(
            id: 'locations',
            label: mobileUi(context, "Locations"),
            icon: Icons.place_outlined,
            screen: LocationsTab(),
          ),
          ManageWorkspaceDestination(
            id: 'requests',
            label: mobileUi(context, "Requests"),
            icon: Icons.calendar_month_outlined,
            screen: AdminBookingsTab(),
          ),
          ManageWorkspaceDestination(
            id: 'reports',
            label: mobileUi(context, "Reports"),
            icon: Icons.report_outlined,
            screen: ReportsTab(),
          ),
          ManageWorkspaceDestination(
            id: 'promotions',
            label: mobileUi(context, "Promotions"),
            icon: Icons.campaign_outlined,
            screen: PromotionsTab(),
          ),
          ManageWorkspaceDestination(
            id: 'growth',
            label: mobileUi(context, "Growth Ops"),
            icon: Icons.monitor_heart_outlined,
            screen: AdminGrowthOperationsScreen(access: access),
          ),
          ManageWorkspaceDestination(
            id: 'notifications',
            label: mobileUi(context, "Notifications"),
            icon: Icons.notifications_outlined,
            screen: NotificationsScreen(),
          ),
          ManageWorkspaceDestination(
            id: 'profile',
            label: mobileUi(context, "Profile"),
            icon: Icons.person_outline,
            screen: ProfileScreen(),
          ),
        ];
    destinations.removeWhere(
      (destination) => !access.allowsDestination(destination.id!),
    );
    if (_currentIndex >= destinations.length) _currentIndex = 0;
    return ManageWorkspaceScaffold(
      title: destinations[_currentIndex].label,
      currentIndex: _currentIndex,
      onSelect: (int index) => setState(() {
        _currentIndex = index;
      }),
      destinations: destinations,
    );
  }
}
