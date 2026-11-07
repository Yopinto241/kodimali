import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_core/lodge_api.dart';
import 'package:manage_mobile/features/lodges/lodge_workspace_screen.dart';

class LodgeFixture extends LodgeApi {
  LodgeFixture({this.housekeeping = false})
    : super(
        SupabaseClient(
          'https://fixture.invalid',
          'fixture-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final bool housekeeping;
  final sections = <String>[];
  @override
  Future<Map<String, String>> images(List<String> paths) async => {};
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
  }) async {
    sections.add(section);
    if (lodgeId == null) {
      return {
        'lodges': [
          {
            'id': 'fixture',
            'name': 'Safari Lodge',
            'location_label': 'Arusha',
            'verification_status': 'pending',
          },
        ],
      };
    }
    return {
      'lodge': {
        'id': 'fixture',
        'name': 'Safari Lodge',
        'timezone': 'Africa/Dar_es_Salaam',
      },
      'permissions': housekeeping ? ['rooms.read', 'rooms.condition'] : ['*'],
      'rows': section == 'rooms'
          ? [
              {
                'id': 'room',
                'code': '101',
                'room_type': 'Standard',
                'max_occupancy': 2,
                'beds': 'Double',
                'currency': 'TZS',
                'nightly_rate': 10000,
                'condition': 'ready',
                'active': true,
              },
            ]
          : section=='room-types'?[{'id':'type','name':'Standard','description':'Configured type','currency':'TZS','nightly_rate':10000,'total_rooms':1,'occupied_rooms':0,'ready_now':1,'available_rooms':1}]:[],
      'total': section == 'rooms' ? 1 : 0,
    };
  }
}

void main() {
  for (final width in [390.0, 720.0]) {
    testWidgets('lodge rooms use a dedicated route at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = LodgeFixture();
      final router = GoRouter(
        initialLocation: '/lodges',
        routes: [
          GoRoute(
            path: '/lodges',
            builder: (_, s) => LodgeWorkspaceScreen(api: api),
          ),
          GoRoute(
            path: '/lodges/:id/:section',
            builder: (_, s) => LodgeWorkspaceScreen(
              api: api,
              lodgeId: s.pathParameters['id'],
              section: s.pathParameters['section']!,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Safari Lodge'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Rooms'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/lodges/fixture/rooms',
      );
      expect(find.text('101 / Standard'), findsOneWidget);
      expect(find.text('Add room'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip,'Room types'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path,'/lodges/fixture/room-types');
      expect(find.text('Configured type'),findsOneWidget);
      expect(find.text('Add room type'),findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'housekeeping navigation excludes guest, payment and staff pages',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LodgeWorkspaceScreen(
            api: LodgeFixture(housekeeping: true),
            lodgeId: 'fixture',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, 'Rooms'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Calendar'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Guests'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Payments'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Staff'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
