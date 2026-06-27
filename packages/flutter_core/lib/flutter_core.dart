class FeatureHighlight {
  const FeatureHighlight({
    required this.title,
    required this.description,
    required this.emphasis,
  });

  final String title;
  final String description;
  final String emphasis;
}

class DashboardMetric {
  const DashboardMetric({
    required this.label,
    required this.value,
    required this.note,
  });

  final String label;
  final String value;
  final String note;
}
