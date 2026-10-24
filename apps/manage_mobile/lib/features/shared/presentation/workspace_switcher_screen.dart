import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import '../../../core/widgets/app_scope.dart';

class WorkspaceSwitcherScreen extends StatelessWidget {
  const WorkspaceSwitcherScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose workspace')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: controller.workspaceRoles
            .map(
              (role) => Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(18),
                  leading: Icon(switch (role) {
                    AppRole.admin => Icons.admin_panel_settings_outlined,
                    AppRole.agent => Icons.badge_outlined,
                    AppRole.owner => Icons.home_work_outlined,
                    _ => Icons.person_outline,
                  }),
                  title: Text(switch (role) {
                    AppRole.admin => 'Administrator',
                    AppRole.agent => 'Agent',
                    AppRole.owner => 'Owner',
                    _ => 'Customer',
                  }),
                  subtitle: const Text(
                    'Continue with this role using the same account.',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () {
                    controller.selectWorkspace(role);
                    context.go(switch (role) {
                      AppRole.admin => '/admin',
                      AppRole.agent => '/agent',
                      AppRole.owner => '/owner',
                      _ => '/access-denied',
                    });
                  },
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
