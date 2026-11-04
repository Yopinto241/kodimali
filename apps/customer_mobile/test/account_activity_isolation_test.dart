import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:customer_mobile/core/cache/customer_activity_store.dart';

void main() {
  test(
    'guest merge is explicit; A/B snapshots, tombstones and restarts stay separate',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = CustomerActivityStore.instance;
      await store.initialize(prefs);
      await store.toggleSaved({'id': 'guest'});
      await store.switchAccount('A');
      expect(store.savedListingIds, isEmpty);
      await store.mergeGuestActivity();
      expect(store.savedListingIds, {'guest'});
      await store.toggleSaved({'id': 'A-only'});
      await store.switchAccount(null);
      expect(store.savedListingIds, isEmpty);
      await store.switchAccount('B');
      expect(store.savedListingIds, isEmpty);
      expect(store.pendingChanges, isEmpty);
      await store.toggleSaved({'id': 'B-only'});
      await store.switchAccount('A');
      expect(store.savedListingIds, {'guest', 'A-only'});
      await store.toggleSaved({'id': 'A-only'});
      expect(store.pendingChanges['A-only'], isFalse);
      await store.initialize(prefs, userId: 'A');
      expect(store.pendingChanges['A-only'], isFalse);
      await store.acknowledgeSaved('A-only', false, forUser: 'B');
      expect(store.pendingChanges['A-only'], isFalse);
      await store.acknowledgeSaved('A-only', false, forUser: 'A');
      expect(store.pendingChanges.containsKey('A-only'), isFalse);
      await store.setSavedFromRemote({'remote'});
      expect(store.savedListingIds, {'remote'});
      await store.switchAccount('B');
      expect(store.savedListingIds, {'B-only'});
    },
  );
  test(
    'ambiguous v1 device-global data is retained but never auto-attributed',
    () async {
      SharedPreferences.setMockInitialValues({
        'customer_saved_listing_snapshots_v1': '[{"id":"private-old"}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = CustomerActivityStore.instance;
      await store.initialize(prefs, userId: 'new-user');
      expect(store.savedListingIds, isEmpty);
      expect(
        prefs.getString('customer_saved_listing_snapshots_v1'),
        contains('private-old'),
      );
    },
  );
}
