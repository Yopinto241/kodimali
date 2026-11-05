import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:customer_mobile/app.dart';
import 'package:customer_mobile/core/data/customer_public_repository.dart';
import 'mobile_ui_test.dart' show host;
import 'location_ads_whatsapp_test.dart' show FixtureRepository;

class DiscoveryRepository extends FixtureRepository {
  DiscoveryRepository(super.client);
  final requests = <JsonMap>[];
  bool paid = false;
  @override
  JsonMap? savedListingDetail(String listingId) => null;
  @override
  Future<bool> fetchContactPaymentsEnabled() async => paid;
  @override
  Future<JsonMap> fetchContactQuote(String id) async => {
    'paymentRequired': paid,
    if (!paid) 'phoneNumber': '255712345678',
    if (paid) 'amount': 1500,
  };
  @override
  Future<JsonMap> fetchListingDetail(
    String id, {
    bool forceRefresh = false,
  }) async => {
    'id': id,
    'title': 'Arusha family house',
    'description': 'A comfortable house near local services.',
    'public_location_label': 'Arusha',
    'price_amount': 200000,
    'price_period': 'month',
    'booking_mode': 'not_bookable',
    'asset_categories': {'name': 'Houses', 'slug': 'houses'},
    'agent_summary': {
      'display_name': 'Fixture Agent',
      'verification_status': 'approved',
    },
  };
  @override
  Future<List<JsonMap>> suggestLocations(String query) async => query.isEmpty
      ? []
      : [
          {
            'location_id': 'region-arusha',
            'name': 'Arusha',
            'label': 'Arusha, Tanzania',
            'location_type': 'region',
          },
        ];
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
    requests.add({
      'page': page,
      'region': regionId,
      'query': searchText,
      'latitude': latitude,
    });
    return List.generate(
      page == 0 ? 40 : 3,
      (index) => {
        'listing_id': '$page-$index',
        'title': 'Home $page-$index',
        'category_name': 'Houses',
        'public_location_label': 'Arusha',
        'price_amount': 100000,
        'price_period': 'month',
      },
    );
  }
}

void main() {
  late SupabaseClient client;
  late DiscoveryRepository repository;
  setUp(() {
    client = SupabaseClient(
      'https://fixture.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    repository = DiscoveryRepository(client);
  });
  tearDown(() => client.dispose());

  testWidgets(
    'search loads another page and a location suggestion replaces GPS scope',
    (tester) async {
      await tester.pumpWidget(
        host(
          Scaffold(
            body: PublicSearchScreen(
              repository: repository,
              initialQuery: 'arusha',
              regionId: null,
              districtId: null,
              wardId: null,
              areaId: null,
              latitude: -3.3,
              longitude: 36.7,
              refreshTick: 0,
            ),
          ),
          'en',
          KodimaliTheme.mobileLight(),
          1,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arusha, Tanzania'));
      await tester.pumpAndSettle();
      expect(repository.requests.last['region'], 'region-arusha');
      expect(repository.requests.last['latitude'], isNull);
      expect(repository.requests.last['query'], isNull);
      await tester.scrollUntilVisible(
        find.text('Load more results'),
        600,
        scrollable: find.byType(Scrollable).last,
        maxScrolls: 80,
      );
      await tester.tap(find.text('Load more results'));
      await tester.pumpAndSettle();
      expect(repository.requests.last['page'], 1);
      expect(find.text('Load more results'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final paid in [false, true]) {
    testWidgets(
      paid
          ? 'paid contact offers number access and WhatsApp without exposing the number'
          : 'free contact displays the number and call action',
      (tester) async {
        repository.paid = paid;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          host(
            ListingDetailScreen(repository: repository, listingId: 'fixture'),
            'en',
            KodimaliTheme.mobileLight(),
            1.3,
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Fixture Agent'),
          350,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        if (paid) {
          expect(find.text('255712345678'), findsNothing);
          expect(find.text('Call / View number'), findsOneWidget);
        } else {
          expect(find.text('255712345678'), findsOneWidget);
          expect(find.byTooltip('Call'), findsOneWidget);
          expect(find.text('Call / View number'), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
