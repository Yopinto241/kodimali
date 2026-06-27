import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

class KodimaliStatusChip extends StatelessWidget {
  const KodimaliStatusChip({
    super.key,
    required this.label,
    this.highlight = false,
    this.tone,
  });

  final String label;
  final bool highlight;
  final KodimaliStatusTone? tone;

  @override
  Widget build(BuildContext context) {
    return KodimaliStatusBadge(
      label: label,
      tone: tone ?? (highlight ? KodimaliStatusTone.active : _inferTone(label)),
    );
  }

  KodimaliStatusTone _inferTone(String rawLabel) {
    final String normalized = rawLabel.toLowerCase();
    if (normalized.contains("active") ||
        normalized.contains("verified") ||
        normalized.contains("approved") ||
        normalized.contains("available")) {
      return KodimaliStatusTone.active;
    }
    if (normalized.contains("pending") ||
        normalized.contains("review") ||
        normalized.contains("new")) {
      return KodimaliStatusTone.pending;
    }
    if (normalized.contains("error") ||
        normalized.contains("rejected") ||
        normalized.contains("suspend") ||
        normalized.contains("cancel")) {
      return KodimaliStatusTone.danger;
    }
    if (normalized.contains("draft") ||
        normalized.contains("inactive") ||
        normalized.contains("archived")) {
      return KodimaliStatusTone.muted;
    }
    return KodimaliStatusTone.info;
  }
}
