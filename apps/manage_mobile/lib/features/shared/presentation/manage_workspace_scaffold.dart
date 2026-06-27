import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

import '../../../core/widgets/app_scope.dart';
import '../../../core/models/app_profile.dart';

class ManageWorkspaceDestination {
  const ManageWorkspaceDestination({
    required this.label,
    required this.icon,
    required this.screen,
  });

  final String label;
  final IconData icon;
  final Widget screen;
}

class ManageWorkspaceScaffold extends StatelessWidget {
  const ManageWorkspaceScaffold({
    super.key,
    required this.title,
    required this.currentIndex,
    required this.onSelect,
    required this.destinations,
  });

  final String title;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<ManageWorkspaceDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.of(context).controller.profile;
    final bool useSidebar = MediaQuery.of(context).size.width >= 960;
    final Widget content = IndexedStack(
      index: currentIndex,
      children: destinations
          .map((ManageWorkspaceDestination item) => item.screen)
          .toList(),
    );

    if (!useSidebar) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: KodimaliSpacing.md),
              child: Center(
                child: KodimaliStatusBadge(
                  label: profile?.highestRole.displayLabel ?? "WORKSPACE",
                  tone: KodimaliStatusTone.info,
                ),
              ),
            ),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: _WorkspaceMenu(
              title: "KODIMALI",
              subtitle: profile?.fullName ?? "Manage App",
              currentIndex: currentIndex,
              destinations: destinations,
              onSelect: (int index) {
                Navigator.of(context).pop();
                onSelect(index);
              },
            ),
          ),
        ),
        body: SafeArea(child: content),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: <Widget>[
            Container(
              width: 300,
              padding: const EdgeInsets.all(KodimaliSpacing.md),
              color: Theme.of(context).colorScheme.surface,
              child: _WorkspaceMenu(
                title: "KODIMALI",
                subtitle: profile?.fullName ?? "Manage App",
                currentIndex: currentIndex,
                destinations: destinations,
                onSelect: onSelect,
              ),
            ),
            Container(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: Column(
                children: <Widget>[
                  Container(
                    margin: const EdgeInsets.fromLTRB(
                      KodimaliSpacing.lg,
                      KodimaliSpacing.lg,
                      KodimaliSpacing.lg,
                      0,
                    ),
                    padding: const EdgeInsets.fromLTRB(
                      KodimaliSpacing.lg,
                      KodimaliSpacing.lg,
                      KodimaliSpacing.lg,
                      KodimaliSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(KodimaliRadii.hero),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      boxShadow: KodimaliShadows.soft(KodimaliColors.navy),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const KodimaliStatusBadge(
                                label: "Focused workspace",
                                tone: KodimaliStatusTone.info,
                              ),
                              const SizedBox(height: KodimaliSpacing.sm),
                              Text(
                                title,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: KodimaliSpacing.xs),
                              Text(
                                "Focused workspace for listings, requests, approvals, and account activity.",
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: KodimaliSpacing.md),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            KodimaliStatusBadge(
                              label:
                                  profile?.highestRole.displayLabel ??
                                  "WORKSPACE",
                              tone: KodimaliStatusTone.active,
                            ),
                            if (profile != null) ...<Widget>[
                              const SizedBox(height: KodimaliSpacing.sm),
                              Text(
                                profile.fullName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        KodimaliSpacing.lg,
                        KodimaliSpacing.md,
                        KodimaliSpacing.lg,
                        KodimaliSpacing.lg,
                      ),
                      child: content,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceMenu extends StatelessWidget {
  const _WorkspaceMenu({
    required this.title,
    required this.subtitle,
    required this.currentIndex,
    required this.destinations,
    required this.onSelect,
  });

  final String title;
  final String subtitle;
  final int currentIndex;
  final List<ManageWorkspaceDestination> destinations;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KodimaliRadii.hero),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              KodimaliSpacing.lg,
              KodimaliSpacing.lg,
              KodimaliSpacing.lg,
              KodimaliSpacing.md,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[
                  KodimaliColors.navy,
                  KodimaliColors.blueSurface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(KodimaliRadii.hero),
                topRight: Radius.circular(KodimaliRadii.hero),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const KodimaliStatusBadge(
                  label: "Primary navigation",
                  tone: KodimaliStatusTone.active,
                ),
                const SizedBox(height: KodimaliSpacing.sm),
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: KodimaliSpacing.xs),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(KodimaliSpacing.sm),
              itemCount: destinations.length,
              itemBuilder: (BuildContext context, int index) {
                final ManageWorkspaceDestination item = destinations[index];
                final bool selected = index == currentIndex;
                return Padding(
                  padding: const EdgeInsets.only(bottom: KodimaliSpacing.xs),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.secondaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(KodimaliRadii.card),
                      border: Border.all(
                        color: selected
                            ? KodimaliColors.green.withValues(alpha: 0.3)
                            : Colors.transparent,
                      ),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(KodimaliRadii.card),
                      ),
                      leading: Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          color: selected
                              ? KodimaliColors.green.withValues(alpha: 0.16)
                              : theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          item.icon,
                          color: selected
                              ? KodimaliColors.navy
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      title: Text(
                        item.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: selected
                              ? KodimaliColors.navy
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      onTap: () => onSelect(index),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
