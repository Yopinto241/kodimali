import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

void main() {
  test('light theme uses KODIMALI navy as the secure primary color', () {
    final theme = KodimaliTheme.light();

    expect(theme.colorScheme.primary, KodimaliColors.navy);
    expect(theme.scaffoldBackgroundColor, KodimaliColors.background);
  });

  test('dark theme keeps the brand green for active emphasis', () {
    final theme = KodimaliTheme.dark();

    expect(theme.colorScheme.primary, KodimaliColors.green);
  });
}
