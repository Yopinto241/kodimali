import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

class ManagePageScrollView extends StatelessWidget {
  const ManagePageScrollView({
    super.key,
    required this.children,
    this.onRefresh,
    this.padding = KodimaliSpacing.screenPadding,
  });

  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final Widget listView = ListView(
      physics: onRefresh == null
          ? const AlwaysScrollableScrollPhysics()
          : const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
      padding: padding,
      children: children,
    );
    if (onRefresh == null) {
      return listView;
    }
    return RefreshIndicator(onRefresh: onRefresh!, child: listView);
  }
}

class ManageHeroCard extends StatelessWidget {
  const ManageHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.bottom,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KodimaliSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[
            KodimaliColors.navy,
            KodimaliColors.blueSurface,
            KodimaliColors.blueSurfaceStrong,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(KodimaliRadii.hero),
        boxShadow: KodimaliShadows.lifted(KodimaliColors.navy),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const KodimaliStatusBadge(
                      label: "Trusted workspace",
                      tone: KodimaliStatusTone.info,
                    ),
                    const SizedBox(height: KodimaliSpacing.sm),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: KodimaliSpacing.xs),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: KodimaliSpacing.md),
                trailing!,
              ],
            ],
          ),
          if (bottom != null) ...<Widget>[
            const SizedBox(height: KodimaliSpacing.md),
            bottom!,
          ],
        ],
      ),
    );
  }
}

class ManageMetricGrid extends StatelessWidget {
  const ManageMetricGrid({
    super.key,
    required this.children,
    this.minChildWidth = 220,
    this.spacing = KodimaliSpacing.sm,
  });

  final List<Widget> children;
  final double minChildWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableWidth = constraints.maxWidth;
        final int columns = (availableWidth / minChildWidth).floor().clamp(
          1,
          4,
        );
        final double totalSpacing = spacing * (columns - 1);
        final double childWidth = (availableWidth - totalSpacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: children
              .map(
                (Widget child) => SizedBox(
                  width: childWidth.isFinite ? childWidth : availableWidth,
                  child: child,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class ManageMetricCard extends StatefulWidget {
  const ManageMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.tint,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? caption;
  final Color? tint;
  final VoidCallback? onTap;

  @override
  State<ManageMetricCard> createState() => _ManageMetricCardState();
}

class _ManageMetricCardState extends State<ManageMetricCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tint = widget.tint ?? theme.colorScheme.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(KodimaliRadii.card),
          border: Border.all(
            color: _hovered
                ? tint.withValues(alpha: 0.24)
                : theme.colorScheme.outlineVariant,
          ),
          boxShadow: KodimaliShadows.soft(tint),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(KodimaliRadii.card),
            child: Padding(
              padding: const EdgeInsets.all(KodimaliSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(widget.icon, color: tint),
                  ),
                  const SizedBox(height: KodimaliSpacing.md),
                  Text(
                    widget.value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(widget.label, style: theme.textTheme.titleMedium),
                  if (widget.caption != null) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(widget.caption!, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ManagePanel extends StatelessWidget {
  const ManagePanel({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.action,
    this.padding = const EdgeInsets.all(KodimaliSpacing.md),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (title != null ||
                subtitle != null ||
                action != null) ...<Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (title != null)
                          Text(title!, style: theme.textTheme.titleLarge),
                        if (subtitle != null) ...<Widget>[
                          if (title != null) const SizedBox(height: 6),
                          Text(subtitle!, style: theme.textTheme.bodyMedium),
                        ],
                      ],
                    ),
                  ),
                  if (action != null) ...<Widget>[
                    const SizedBox(width: KodimaliSpacing.sm),
                    action!,
                  ],
                ],
              ),
              const SizedBox(height: KodimaliSpacing.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class ManageSectionTitle extends StatelessWidget {
  const ManageSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: theme.textTheme.titleLarge),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(subtitle!, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        if (action != null) ...<Widget>[
          const SizedBox(width: KodimaliSpacing.sm),
          action!,
        ],
      ],
    );
  }
}

class ManageMetaWrap extends StatelessWidget {
  const ManageMetaWrap({super.key, required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: KodimaliSpacing.sm,
      runSpacing: KodimaliSpacing.sm,
      children: items
          .where((String item) => item.trim().isNotEmpty)
          .map(
            (String item) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KodimaliSpacing.sm,
                vertical: KodimaliSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(KodimaliRadii.pill),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                item,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
