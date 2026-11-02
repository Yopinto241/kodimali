import 'package:flutter_core/localized_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

import '../../../core/widgets/app_scope.dart';
import '../../../core/models/app_profile.dart';
import '../../../core/localization/manage_localization.dart';

class ManageWorkspaceDestination {
  const ManageWorkspaceDestination({
    required this.label,
    required this.icon,
    required this.screen,
    this.id,
  });

  final String label;
  final IconData icon;
  final Widget screen;
  final String? id;
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
    final controller = AppScope.of(context).controller;
    final profile = controller.profile;
    final bool useSidebar = MediaQuery.of(context).size.width >= 960;
    final Widget content = _WorkspacePages(
      index: currentIndex,
      destinations: destinations,
      onSelect: onSelect,
    );

    if (!useSidebar) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            context.tr(destinations[currentIndex].label),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          actions: <Widget>[const ManageLanguageButton()],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: _WorkspaceMenu(
              title: mobileUi(context, "KODIMALI"),
              subtitle: profile?.fullName ?? context.tr("Manage App"),
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
                title: mobileUi(context, "KODIMALI"),
                subtitle: profile?.fullName ?? context.tr("Manage App"),
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
                              KodimaliStatusBadge(
                                label: context.tr("Focused workspace"),
                                tone: KodimaliStatusTone.info,
                              ),
                              const SizedBox(height: KodimaliSpacing.sm),
                              Text(
                                context.tr(title),
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: KodimaliSpacing.xs),
                              Text(
                                context.tr(
                                  "Focused workspace for listings, requests, approvals, and account activity.",
                                ),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: KodimaliSpacing.md),
                        const ManageLanguageButton(),
                        const SizedBox(width: KodimaliSpacing.sm),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            KodimaliStatusBadge(
                              label:
                                  controller.highestRole?.displayLabel ??
                                  context.tr("WORKSPACE"),
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

// Only instantiate visited destinations. Inactive modules retain their filters
// and scroll position without fetching every administrative table at startup.
class _WorkspacePages extends StatefulWidget {
  const _WorkspacePages({
    required this.index,
    required this.destinations,
    required this.onSelect,
  });
  final int index;
  final List<ManageWorkspaceDestination> destinations;
  final ValueChanged<int> onSelect;
  @override
  State<_WorkspacePages> createState() => _WorkspacePagesState();
}

class _WorkspacePagesState extends State<_WorkspacePages> {
  final Set<int> _visited = {};
  final List<int> _history = [];
  bool _goingBack = false;
  @override
  void initState() {
    super.initState();
    _visited.add(widget.index);
  }

  @override
  void didUpdateWidget(_WorkspacePages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      if (!_goingBack) _history.add(oldWidget.index);
      _goingBack = false;
      _visited.add(widget.index);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _history.isEmpty,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _history.isNotEmpty) {
        _goingBack = true;
        widget.onSelect(_history.removeLast());
      }
    },
    child: IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.destinations.length; i++)
          _visited.contains(i)
              ? TickerMode(
                  enabled: widget.index == i,
                  child: KeyedSubtree(
                    key: ValueKey(
                      widget.destinations[i].id ??
                          '$i:${widget.destinations[i].screen.runtimeType}',
                    ),
                    child: widget.destinations[i].screen,
                  ),
                )
              : const SizedBox.shrink(),
      ],
    ),
  );
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
                KodimaliStatusBadge(
                  label: context.tr("Primary navigation"),
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
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      title: Text(
                        context.tr(item.label),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: selected
                              ? theme.colorScheme.onSecondaryContainer
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
