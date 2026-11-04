String notificationDestination(Map<String, dynamic> data) {
  final route = (data['route'] ?? '').toString().replaceFirst(
    RegExp(r'^/'),
    '',
  );
  final parts = route.split('/');
  final pathId = parts.length > 1 ? parts.last : '';
  final rawId = RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(pathId)
      ? pathId
      : (data['bookingId'] ??
                data['listingId'] ??
                data['eventPlanId'] ??
                data['paymentId'] ??
                '')
            .toString();
  final id = RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(rawId) ? rawId : '';
  if (parts.first == 'chat' && id.isNotEmpty) return '/listing-chat/$id';
  final kind = switch (parts.first) {
    'booking' || 'bookings' || 'request' || 'requests' => 'booking',
    'listing' || 'listings' => 'listing',
    'payment' || 'payments' || 'business' => 'payments',
    'event' || 'events' || 'account' => 'events',
    _ => data['bookingId'] != null ? 'booking' : 'notifications',
  };
  return '/notification/$kind/${id.isEmpty ? 'overview' : id}';
}
