import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:customer_mobile/features/chat/listing_chat_screens.dart';
import 'production_repair_test.dart' show AuditRepository;
import 'mobile_ui_test.dart' show host;

class AccessRepository extends AuditRepository {
  AccessRepository(super.client);
  bool enabled = false, entitled = false, unavailable = false;
  int starts = 0;
  @override
  bool get isSignedIn => true;
  @override
  Future<bool> fetchChatPaymentsEnabled() async {
    if (unavailable) throw StateError('Connection unavailable');
    return enabled;
  }

  @override
  Future<int> fetchPaidChatUnlockPrice() async => 2700;
  @override
  Future<bool> hasListingChatAccess(String listingId) async => entitled;
  @override
  Future<Map<String, dynamic>> createListingChatPayment({
    required String listingId,
    required String phoneNumber,
    int? expectedAmount,
  }) async {
    starts++;
    expect(phoneNumber, isEmpty);
    expect(expectedAmount, isNull);
    return {'paymentRequired': false};
  }

  @override
  Future<Map<String, dynamic>> openListingConversation(
    String listingId,
  ) async => {'id': 'fixture-chat'};
}

void main() {
  late SupabaseClient client;
  late AccessRepository repo;
  setUp(() {
    client = SupabaseClient(
      'https://fixture.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    repo = AccessRepository(client);
  });
  tearDown(() async {
    await repo.messages.close();
    await client.dispose();
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      host(
        CustomerListingChatGate(
          repository: repo,
          listingId: 'fixture-listing',
          listingTitle: 'Fixture listing',
          onAuthenticate: (_) async {},
        ),
        'en',
        KodimaliTheme.mobileLight(),
        1,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
  }

  for (final existing in [false, true]) {
    testWidgets(
      existing
          ? 'existing access opens chat without another payment'
          : 'free access opens chat without payment details',
      (tester) async {
        repo.enabled = existing;
        repo.entitled = existing;
        await open(tester);
        expect(repo.starts, 1);
        expect(find.byType(CustomerListingChatScreen), findsOneWidget);
        expect(find.text('Mobile-money phone number'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('paid chat shows current configured price', (tester) async {
    repo.enabled = true;
    await open(tester);
    expect(repo.starts, 0);
    expect(find.text('Mobile-money phone number'), findsOneWidget);
    expect(find.textContaining('2700'), findsWidgets);
    expect(find.textContaining('1000'), findsNothing);
  });
  testWidgets('unknown settings offer retry without a fabricated price', (
    tester,
  ) async {
    repo.unavailable = true;
    await open(tester);
    expect(repo.starts, 0);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Mobile-money phone number'), findsNothing);
  });
}
