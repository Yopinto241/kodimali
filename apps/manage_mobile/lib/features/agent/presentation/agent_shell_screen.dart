import 'package:flutter/material.dart';

import '../../shared/presentation/notifications_screen.dart';
import '../../shared/presentation/manage_workspace_scaffold.dart';
import '../../shared/presentation/profile_screen.dart';
import 'add_asset_screen.dart';
import 'agent_bookings_tab.dart';
import 'agent_dashboard_tab.dart';
import 'agent_listings_tab.dart';

class AgentShellScreen extends StatefulWidget {
  const AgentShellScreen({super.key});

  @override
  State<AgentShellScreen> createState() => _AgentShellScreenState();
}

class _AgentShellScreenState extends State<AgentShellScreen> {
  int _currentIndex = 0;

  static const List<String> _titles = <String>[
    "Dashboard",
    "My Listings",
    "Add Asset",
    "Requests",
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
          screen: AgentDashboardTab(),
        ),
        ManageWorkspaceDestination(
          label: "My Listings",
          icon: Icons.home_work_outlined,
          screen: AgentListingsTab(),
        ),
        ManageWorkspaceDestination(
          label: "Add Asset",
          icon: Icons.add_box_outlined,
          screen: AddAssetScreen(),
        ),
        ManageWorkspaceDestination(
          label: "Requests",
          icon: Icons.calendar_month_outlined,
          screen: AgentBookingsTab(),
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
