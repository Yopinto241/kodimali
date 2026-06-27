import 'package:flutter/material.dart';

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

class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _currentIndex = 0;

  static const List<String> _titles = <String>[
    "Dashboard",
    "Agents",
    "Listings",
    "Categories",
    "Locations",
    "Requests",
    "Reports",
    "Promotions",
    "Notifications",
    "Profile",
  ];

  @override
  Widget build(BuildContext context) {
    return ManageWorkspaceScaffold(
      title: _titles[_currentIndex],
      currentIndex: _currentIndex,
      onSelect: (int index) => setState(() => _currentIndex = index),
      destinations: const <ManageWorkspaceDestination>[
        ManageWorkspaceDestination(
          label: "Dashboard",
          icon: Icons.dashboard_outlined,
          screen: AdminDashboardTab(),
        ),
        ManageWorkspaceDestination(
          label: "Agents",
          icon: Icons.verified_user_outlined,
          screen: AgentVerificationTab(),
        ),
        ManageWorkspaceDestination(
          label: "Listings",
          icon: Icons.rule_folder_outlined,
          screen: ListingApprovalTab(),
        ),
        ManageWorkspaceDestination(
          label: "Categories",
          icon: Icons.category_outlined,
          screen: CategoriesTab(),
        ),
        ManageWorkspaceDestination(
          label: "Locations",
          icon: Icons.place_outlined,
          screen: LocationsTab(),
        ),
        ManageWorkspaceDestination(
          label: "Requests",
          icon: Icons.calendar_month_outlined,
          screen: AdminBookingsTab(),
        ),
        ManageWorkspaceDestination(
          label: "Reports",
          icon: Icons.report_outlined,
          screen: ReportsTab(),
        ),
        ManageWorkspaceDestination(
          label: "Promotions",
          icon: Icons.campaign_outlined,
          screen: PromotionsTab(),
        ),
        ManageWorkspaceDestination(
          label: "Notifications",
          icon: Icons.notifications_outlined,
          screen: NotificationsScreen(),
        ),
        ManageWorkspaceDestination(
          label: "Profile",
          icon: Icons.person_outline,
          screen: ProfileScreen(),
        ),
      ],
    );
  }
}
