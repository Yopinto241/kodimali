import 'package:flutter_test/flutter_test.dart';
import 'package:shared_constants/shared_constants.dart';

void main() {
  test('launch city stays aligned with MVP plan', () {
    expect(mvpLaunchCity, 'Arusha');
  });

  test('media rules keep upload costs controlled', () {
    expect(mediaLimits.first.value, '8');
    expect(mediaLimits[1].value, '1');
  });
}
