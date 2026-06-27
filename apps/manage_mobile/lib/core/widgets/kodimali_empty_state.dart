import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

class KodimaliEmptyState extends StatelessWidget {
  const KodimaliEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KodimaliSpacing.lg),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(KodimaliSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const KodimaliStatusBadge(
                  label: "Nothing to show",
                  tone: KodimaliStatusTone.muted,
                ),
                const SizedBox(height: KodimaliSpacing.sm),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: KodimaliSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (action != null) ...<Widget>[
                  const SizedBox(height: KodimaliSpacing.lg),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
