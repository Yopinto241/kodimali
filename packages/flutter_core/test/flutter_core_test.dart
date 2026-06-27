import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_core/flutter_core.dart';

void main() {
  test('feature highlight keeps descriptive content', () {
    const feature = FeatureHighlight(
      title: 'Verified agents',
      description: 'Only approved wakala can publish listings.',
      emphasis: 'Marketplace trust first',
    );

    expect(feature.title, 'Verified agents');
    expect(feature.emphasis, contains('trust'));
  });
}
