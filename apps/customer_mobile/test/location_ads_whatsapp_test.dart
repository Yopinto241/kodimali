import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:customer_mobile/app.dart';
import 'package:customer_mobile/core/data/customer_public_repository.dart';
import 'package:customer_mobile/core/ads/promotion_tracking.dart';
import 'package:customer_mobile/core/utils/whatsapp.dart';
import 'package:customer_mobile/core/widgets/whatsapp_icon.dart';
import 'mobile_ui_test.dart' show host;
import 'package:flutter_design_system/flutter_design_system.dart';

class FixtureRepository extends CustomerPublicRepository {
  FixtureRepository(super.client);
  Completer<List<JsonMap>>? delayed;
  bool fail = false;
  int detailCalls = 0;
  int paymentChecks = 0;
  JsonMap? saved;
  final searches = <JsonMap>[];
  final ads = <JsonMap>[];
  @override
  Future<List<JsonMap>> fetchCategories() async => [];
  @override
  Future<List<JsonMap>> fetchPublicListings({
    String? categorySlug,
    String? searchText,
    String? regionId,
    String? districtId,
    String? wardId,
    String? areaId,
    int limit = 20,
    int page = 0,
    double? latitude,
    double? longitude,
    String? sessionSeed,
    double? minPrice,
    double? maxPrice,
    String? pricePeriod,
    String sort = 'recommended',
  }) async {
    searches.add({'region': regionId, 'lat': latitude, 'lng': longitude});
    return [];
  }

  @override
  Future<List<JsonMap>> fetchPromotions({
    required String surface,
    String? categorySlug,
    String placement = 'global',
    int limit = 3,
    String? regionId,
    String? districtId,
    String? wardId,
    String? areaId,
  }) async {
    ads.add({'region': regionId});
    return [];
  }

  @override
  Future<List<JsonMap>> fetchLocations({
    required String? parentId,
    required String locationType,
  }) async {
    if (fail) throw StateError('offline');
    if (locationType == 'country') {
      return [
        {'id': 'country', 'name': 'Tanzania'},
      ];
    }
    if (locationType == 'region') {
      return [
        {'id': 'a', 'name': 'Region A'},
        {'id': 'b', 'name': 'Region B'},
      ];
    }
    if (parentId == 'a' && delayed != null) return delayed!.future;
    if (locationType == 'district') {
      return [
        {'id': '${parentId}d', 'name': 'District $parentId'},
      ];
    }
    return [];
  }

  @override
  Future<JsonMap> fetchListingDetail(
    String id, {
    bool forceRefresh = false,
  }) async {
    detailCalls++;
    return {
      'agent_summary': {'display_name': 'Fixture Agent', 'phone_number': null},
    };
  }

  @override
  Future<JsonMap> fetchContactQuote(String id) async => {'paymentRequired':true,'amount':1500,'currency':'TZS'};
  @override
  JsonMap? savedContactAccess(String id) => saved;
  @override
  Future<JsonMap> checkListingContactPayment(String id) async {
    paymentChecks++;
    saved = {'status': 'expired', 'phone_number': null};
    return saved!;
  }
}

void main() {
  late SupabaseClient client;
  setUp(
    () => client = SupabaseClient(
      'https://fixture.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ),
  );
  tearDown(() => client.dispose());
  test('WhatsApp normalizes local and international numbers', () {
    for (final phone in [
      '0712 345 678',
      '712345678',
      '+255 (712) 345-678',
      '00255 712345678',
    ]) {
      expect(normalizeWhatsAppNumber(phone), '255712345678');
    }
    expect(
      whatsAppUri('+44 7700 900123').toString(),
      'https://wa.me/447700900123',
    );
    for (final phone in [
      null,
      '',
      'abc0712345678',
      '123',
      '255712',
      '000000000000',
    ]) {
      expect(whatsAppUri(phone), isNull);
    }
  });
  testWidgets(
    'location handles races, retry, cancel and small landscape screens',
    (tester) async {
      final repo = FixtureRepository(client);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(568, 320);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        host(
          Scaffold(body: LocationSelectorSheet(repository: repo)),
          'en',
          KodimaliTheme.mobileLight(),
          1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final fields = find.byType(DropdownButtonFormField<String>);
      repo.delayed = Completer<List<JsonMap>>();
      tester.widget<DropdownButtonFormField<String>>(fields.at(0)).onChanged!(
        'a',
      );
      await tester.pump();
      tester.widget<DropdownButtonFormField<String>>(fields.at(0)).onChanged!(
        'b',
      );
      await tester.pumpAndSettle();
      repo.delayed!.complete([
        {'id': 'ad', 'name': 'Wrong stale district'},
      ]);
      await tester.pumpAndSettle();
      final district = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: fields.at(1),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(district.items!.map((row) => row.value), contains('bd'));
      expect(district.items!.map((row) => row.value), isNot(contains('ad')));
      expect(find.text('All locations'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(tester.takeException(), isNull);
      repo.fail = true;
      tester.widget<DropdownButtonFormField<String>>(fields.at(0)).onChanged!(
        'a',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Retry'));
      expect(find.text('Retry'), findsOneWidget);
      repo.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
    },
  );
  testWidgets(
    'ad impressions require visible exposure for one second and count once',
    (tester) async {
      var count = 0;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 1000),
                  PromotionExposure(
                    promotionId: 'fixture',
                    onImpression: () => count++,
                    child: const SizedBox(height: 100, width: 200),
                  ),
                  const SizedBox(height: 1000),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(count, 0);
      scroll.jumpTo(950);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(count, 0);
      scroll.jumpTo(0);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(count, 0);
      scroll.jumpTo(950);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(count, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(count, 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('manual search location clears GPS and retargets sponsored ads', (
    tester,
  ) async {
    final repo = FixtureRepository(client);
    await tester.pumpWidget(
      host(
        Scaffold(
          body: PublicSearchScreen(
            repository: repo,
            regionId: null,
            districtId: null,
            wardId: null,
            areaId: null,
            latitude: -3.3,
            longitude: 36.6,
            refreshTick: 0,
          ),
        ),
        'en',
        KodimaliTheme.mobileLight(),
        1,
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.searches.last['lat'], -3.3);
    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.location_on_outlined).first,
        matching: find.byType(ActionChip),
      ),
    );
    await tester.pumpAndSettle();
    final region = find.byType(DropdownButtonFormField<String>).first;
    tester.widget<DropdownButtonFormField<String>>(region).onChanged!('a');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Show results'));
    await tester.tap(find.text('Show results'));
    await tester.pumpAndSettle();
    expect(repo.searches.last, {'region': 'a', 'lat': null, 'lng': null});
    expect(repo.ads.last['region'], 'a');
    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.location_on_outlined).first,
        matching: find.byType(ActionChip),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('All locations'));
    await tester.tap(find.text('All locations'));
    await tester.pumpAndSettle();
    expect(repo.searches.last, {'region': null, 'lat': null, 'lng': null});
    expect(repo.ads.last['region'], isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'WhatsApp card button only appears for available contacts and opens paid unlock',
    (tester) async {
      final repo = FixtureRepository(client);
      Widget card(bool available) => host(
        Scaffold(
          body: SingleChildScrollView(
            child: PublicListingCard(
              repository: repo,
              listing: {
                'listing_id': 'fixture',
                'title': 'Fixture listing',
                'price_amount': 10000,
                'has_whatsapp': available,
              },
            ),
          ),
        ),
        'en',
        KodimaliTheme.mobileLight(),
        1,
      );
      await tester.pumpWidget(card(false));
      await tester.pumpAndSettle();
      expect(find.byType(WhatsAppIcon), findsNothing);
      await tester.pumpWidget(card(true));
      await tester.pumpAndSettle();
      expect(find.byType(WhatsAppIcon), findsOneWidget);
      await tester.ensureVisible(find.byType(WhatsAppIcon));
      await tester.tap(find.byType(WhatsAppIcon));
      await tester.pumpAndSettle();
      expect(repo.detailCalls, 1);
      expect(find.byType(Form), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(Form), findsNothing);
      repo.saved = {
        'status': 'paid',
        'phone_number': '255700000001',
        'payment_id': 'fixture',
      };
      await tester.ensureVisible(find.byType(WhatsAppIcon));
      await tester.tap(find.byType(WhatsAppIcon));
      await tester.pumpAndSettle();
      expect(repo.paymentChecks, 1);
      expect(find.textContaining('255700000001'), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
