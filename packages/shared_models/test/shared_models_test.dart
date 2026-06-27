import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  test('booking status exposes agent delayed storage value', () {
    expect(BookingStatus.agentDelayed.storageValue, 'agent_delayed');
  });

  test('listing summary keeps approximate public location intact', () {
    const listing = ListingSummary(
      title: 'Ukumbi wa Arusha Central',
      category: ListingCategory.meetingHall,
      publicLocationLabel: 'Njiro, Arusha',
      priceLabel: 'TZS 350,000 / day',
      agentName: 'Baraka Rentals',
      availabilityLabel: 'Available this weekend',
    );

    expect(listing.category.displayName, 'Meeting Hall');
    expect(listing.publicLocationLabel, 'Njiro, Arusha');
  });
}
