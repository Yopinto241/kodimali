import 'package:flutter_test/flutter_test.dart';
import 'package:customer_mobile/core/ads/sponsored_layout.dart';

void main() {
  test(
    'many campaigns keep one slot per three listings without dropping or repeating ads',
    () {
      final ads = List.generate(
        109,
        (index) => <String, dynamic>{'promotion_id': 'ad-$index'},
      );
      final result = sponsoredLayout([...ads, ads.first], 31);
      expect(result.inline.length, 10);
      expect(result.remaining.length, 99);
      expect([...result.inline, ...result.remaining], ads);
      for (final count in [0, 1, 2, 3]) {
        expect(sponsoredLayout(ads, count).inline, isEmpty);
        expect(sponsoredLayout(ads, count).remaining, ads);
      }
      expect(sponsoredLayout(ads, 4).inline, [ads.first]);
      expect(sponsoredLayout([], 100).remaining, isEmpty);
    },
  );
}
