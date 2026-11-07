import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_core/lodge_api.dart';
import 'package:flutter_core/lodge_form.dart';
import 'package:flutter_core/lodge_discovery.dart';
import 'package:flutter_core/lodge_errors.dart';

class FixtureLodgeApi extends LodgeApi {
  FixtureLodgeApi({this.detailed = false})
    : super(SupabaseClient('https://fixture.invalid', 'fixture-public-key',authOptions:const AuthClientOptions(autoRefreshToken:false)));
  final calls = <LodgeRow>[];
  final bool detailed;
  bool failOnce = false;
  @override
  Future<LodgeRow> workspace({
    String? lodgeId,
    String section = 'dashboard',
    String? start,
    String? end,
    int offset = 0,
    int limit = 30,
    String query = '',
    String roomType = '',
  }) async => {
    'rows': [
      {
        'id': 'reservation-fixture',
        'code': '101',
        'full_name': 'Fixture guest',
      },
    ],
    'total': 1,
  };
  @override
  Future<dynamic> command(String lodgeId, String action, LodgeRow data) async {
    calls.add(Map.of(data));
    if (failOnce) {
      failOnce = false;
      throw const SocketException('fixture');
    }
    return {'ok': true};
  }

  @override
  Future<Map<String, String>> images(List<String> paths) async => {};
  @override
  Future<LodgeRow> discover({
    String? id,
    String search = '',
    String? locationId,
    String? arrival,
    String? departure,
    int offset = 0,
  }) async => {
    'rows': [
      {
        'id': 'lodge-fixture',
        'name': 'Safari Fixture Lodge',
        'location_label': 'Arusha',
        'phone': '255700000001',
        'facilities': ['WiFi'],
        'photos': [],
        'room_types': [
          {
            'room_type': 'Standard',
            'currency': 'TZS',
            'from_price': 20000,
            'max_occupancy': 2,
            'available_rooms': null,
          },
          if (detailed) {
            'id': 'deluxe-type',
            'room_type': 'Deluxe',
            'description': 'Owner-configured air conditioning',
            'facilities': ['Air conditioning'],
            'currency': 'TZS',
            'from_price': 55000,
            'max_occupancy': 3,
            'available_rooms': 2,
          },
        ],
      },
    ],
    'total': 1,
  };
  @override
  Future<List<LodgeRow>> locations(String text) async => [
    {
      'location_id': 'fixture-location',
      'label': 'Arusha, Tanzania',
      'location_type': 'region',
    },
  ];
}

void main() {
  testWidgets('lodge details show configured type prices and representative placeholders', (tester) async {
    await tester.pumpWidget(MaterialApp(home:LodgeDiscoveryScreen(api:FixtureLodgeApi(detailed:true),lodgeId:'lodge-fixture')));
    await tester.pumpAndSettle();
    expect(find.textContaining('TZS 20000'),findsOneWidget);
    expect(find.textContaining('TZS 55000'),findsOneWidget);
    expect(find.text('Owner-configured air conditioning'),findsOneWidget);
    expect(find.text('No authorized photograph available'),findsNWidgets(2));
    expect(find.text('Request reservation'),findsNWidgets(2));
    expect(tester.takeException(),isNull);
  });
  testWidgets(
    'payment retries preserve one request identifier and form values',
    (tester) async {
      final api = FixtureLodgeApi()..failOnce = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LodgeFormScreen(
                      api: api,
                      action: 'record_payment',
                      lodgeId: 'lodge-fixture',
                      initial: const {'reservation_id': 'reservation-fixture'},
                    ),
                  ),
                ),
                child: const Text('Open payment'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open payment'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount collected'),
        '5000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Payment method description'),
        'Cash',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(api.calls.length, 1);
      expect(find.textContaining('Connection unavailable'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(api.calls.length, 2);
      expect(api.calls[0]['request_id'], api.calls[1]['request_id']);
      expect(api.calls[1]['amount'], 5000);
      expect(api.calls[1]['reservation_id'], 'reservation-fixture');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'room blocks require dates and rooms without collecting guest information',
    (tester) async {
      final api = FixtureLodgeApi();
      await tester.pumpWidget(
        MaterialApp(
          home: LodgeFormScreen(
            api: api,
            action: 'block_room',
            lodgeId: 'fixture',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Guest name'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Arrival'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Departure'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month_outlined), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('public lodge browsing does not require choosing a location', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: LodgeDiscoveryScreen(api: FixtureLodgeApi())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Safari Fixture Lodge'), findsOneWidget);
    expect(find.text('Ask the lodge to confirm availability.'), findsOneWidget);
    expect(find.text('View lodge'), findsOneWidget);
    expect(find.textContaining('Pay to'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('conflict errors reveal no database or guest details', () {
    final message = lodgeUserMessage(
      const PostgrestException(
        message: 'private fixture guest in exclusion constraint',
        code: '23P01',
      ),
    );
    expect(message, contains('already reserved'));
    expect(message, isNot(contains('private fixture')));
  });
}
