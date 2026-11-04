import 'package:flutter_test/flutter_test.dart';
import 'package:manage_mobile/core/router/notification_destination.dart';

void main() {
  const id = '11111111-1111-4111-8111-111111111111';
  test(
    'notification types retain their resource across cold-start payloads',
    () {
      expect(
        notificationDestination({'route': 'chat/$id'}),
        '/listing-chat/$id',
      );
      expect(
        notificationDestination({'bookingId': id}),
        '/notification/booking/$id',
      );
      expect(
        notificationDestination({'route': 'listing/$id'}),
        '/notification/listing/$id',
      );
      expect(
        notificationDestination({'route': 'account/events', 'eventPlanId': id}),
        '/notification/events/$id',
      );
      expect(
        notificationDestination({'route': 'payments', 'paymentId': id}),
        '/notification/payments/$id',
      );
    },
  );
  test('untrusted routes and malformed identifiers fall back safely', () {
    expect(
      notificationDestination({'route': 'https://evil.invalid/steal'}),
      '/notification/notifications/overview',
    );
    expect(
      notificationDestination({'route': 'booking/../../private'}),
      '/notification/booking/overview',
    );
  });
}
