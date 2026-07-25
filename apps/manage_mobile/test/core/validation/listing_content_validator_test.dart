import 'package:flutter_test/flutter_test.dart';
import 'package:manage_mobile/core/validation/listing_content_validator.dart';

void main() {
  group('ListingContentValidator', () {
    test('matches the database title constraint', () {
      expect(ListingContentValidator.titleError('ab'), isNotNull);
      expect(ListingContentValidator.titleError('Valid title'), isNull);
      expect(ListingContentValidator.titleError('x' * 181), isNotNull);
    });

    test('requires ten trimmed description characters', () {
      expect(ListingContentValidator.descriptionError('short'), isNotNull);
      expect(ListingContentValidator.descriptionError(' 1234567890 '), isNull);
      expect(
        ListingContentValidator.requireValidDescription(' 1234567890 '),
        '1234567890',
      );
    });

    test('throws a friendly error before a database write', () {
      expect(
        () => ListingContentValidator.requireValidDescription('too short'),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('at least 10 characters'),
          ),
        ),
      );
    });
  });
}
