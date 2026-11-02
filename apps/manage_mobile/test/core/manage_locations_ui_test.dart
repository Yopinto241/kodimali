import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:manage_mobile/core/data/manage_repository.dart';
import 'package:manage_mobile/features/admin/presentation/locations_tab.dart';
import 'package:manage_mobile/features/admin/presentation/users_tab.dart';
import 'package:manage_mobile/features/admin/presentation/admin_shell_screen.dart';
import 'package:manage_mobile/features/admin/presentation/admin_workspace_access.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_core/localized_ui.dart';
import 'package:manage_mobile/core/config/app_dependencies.dart';
import 'package:manage_mobile/core/state/app_controller.dart';
import 'package:manage_mobile/core/widgets/app_scope.dart';
import 'package:manage_mobile/core/widgets/manage_ui.dart';
import 'package:manage_mobile/core/widgets/kodimali_status_chip.dart';
import 'package:manage_mobile/core/localization/manage_localization.dart';
import 'package:manage_mobile/features/shared/presentation/manage_workspace_scaffold.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FixtureLocations extends ManageRepository {
  FixtureLocations(super.client);
  final calls = <String?>[];
  final rows = <Map<String, dynamic>>[
    {
      'id': 'country',
      'parent_id': null,
      'name': 'Tanzania',
      'location_type': 'country',
      'is_active': true,
    },
    {
      'id': 'region',
      'parent_id': 'country',
      'name': 'Arusha',
      'location_type': 'region',
      'is_active': true,
    },
    {
      'id': 'district',
      'parent_id': 'region',
      'name': 'Arusha District',
      'location_type': 'district',
      'is_active': true,
    },
    {
      'id': 'ward',
      'parent_id': 'district',
      'name': 'Sokoni',
      'location_type': 'ward',
      'is_active': true,
    },
    {
      'id': 'area',
      'parent_id': 'ward',
      'name': 'Central',
      'location_type': 'area',
      'is_active': true,
    },
  ];
  @override
  Future<JsonMap> fetchLocationCountryForAdmin() async => rows.first;
  @override
  Future<List<JsonMap>> fetchLocationChildren({
    String? parentId,
    String search = '',
    int offset = 0,
    int limit = 20,
  }) async {
    calls.add(parentId);
    return rows
        .where(
          (row) =>
              row['parent_id'] == parentId &&
              row['name'].toString().contains(search),
        )
        .skip(offset)
        .take(limit)
        .toList();
  }

  @override
  Future<void> addLocation({
    required String name,
    required LocationType type,
    required String? parentId,
  }) async {
    rows.add({
      'id': 'new',
      'parent_id': parentId,
      'name': name,
      'location_type': type.name,
      'is_active': true,
    });
  }

  @override
  Future<void> renameLocation({
    required String id,
    required String name,
  }) async {
    rows.firstWhere((row) => row['id'] == id)['name'] = name;
  }
}

class FixtureUsers extends ManageRepository {
  FixtureUsers(super.client);
  @override
  Future<List<JsonMap>> fetchAdminCustomerUsers({
    int limit = 100,
    int offset = 0,
    String search = '',
    String? confirmation,
  }) async =>
      [
            for (var i = 1; i <= 45; i++)
              {
                'id': '$i',
                'full_name': 'Customer $i',
                'account_email': 'customer$i@example.invalid',
                'phone_number': '255700000000',
                'preferred_language': 'sw',
                'created_at': '2026-01-01T00:00:00Z',
              },
          ]
          .where((row) => row['full_name']!.contains(search))
          .skip(offset)
          .take(limit)
          .toList();
}

class FixtureRestrictedAdmin extends FixtureLocations {
  FixtureRestrictedAdmin(super.client);
  @override
  Future<Set<String>> fetchMyAdminPermissions() async => {};
  @override
  Future<List<JsonMap>> fetchNotifications() async => [];
}

class ProbeScreen extends StatefulWidget {
  const ProbeScreen({super.key, required this.onMount});
  final VoidCallback onMount;
  @override
  State<ProbeScreen> createState() => _ProbeState();
}

class _ProbeState extends State<ProbeScreen> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late SupabaseClient client;
  setUpAll(() {
    client = SupabaseClient(
      'https://fixture.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() => client.dispose());

  test('module permissions use stable IDs and deny unknown destinations', () {
    const finance = AdminWorkspaceAccess({'payments.manage'});
    expect(finance.allowsDestination('contributor-rewards'), isTrue);
    for (final id in [
      'users',
      'listings',
      'locations',
      'information',
      'unknown',
    ]) {
      expect(finance.allowsDestination(id), isFalse);
    }
    const customerDirectory = AdminWorkspaceAccess({'users.view'});
    expect(customerDirectory.allowsDestination('users'), isTrue);
    expect(customerDirectory.allowsDestination('contributor-rewards'), isFalse);
  });

  for (final language in ['en', 'sw']) {
    testWidgets('unassigned admin cannot see restricted modules in $language', (
      tester,
    ) async {
      final repo = FixtureRestrictedAdmin(client);
      final controller = AppController(repo);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, state) => const SizedBox.shrink()),
        ],
      );
      addTearDown(controller.dispose);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ManageLanguageScope(
          languageCode: language,
          onChanged: (_) async {},
          child: AppScope(
            dependencies: AppDependencies(
              repository: repo,
              controller: controller,
              router: router,
            ),
            child: MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('en'), Locale('sw')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: KodimaliTheme.mobileLight(),
              home: const AdminShellScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      final drawer = find.byType(Drawer);
      expect(
        find.descendant(of: drawer, matching: find.byType(ListTile)),
        findsNWidgets(2),
      );
      for (final label in [
        'Users',
        'Listings',
        'Locations',
        'Information Administration',
      ]) {
        expect(
          find.descendant(
            of: drawer,
            matching: find.text(translateMobileUi(language, label)),
          ),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'inactive and unverified records never receive the active badge tone',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: KodimaliTheme.mobileLight(),
          home: const Scaffold(
            body: Column(
              children: [
                KodimaliStatusChip(label: 'active', highlight: true),
                KodimaliStatusChip(label: 'inactive', highlight: true),
                KodimaliStatusChip(label: 'unverified', highlight: true),
              ],
            ),
          ),
        ),
      );
      expect(
        tester
            .widgetList<KodimaliStatusBadge>(find.byType(KodimaliStatusBadge))
            .map((badge) => badge.tone),
        [
          KodimaliStatusTone.active,
          KodimaliStatusTone.muted,
          KodimaliStatusTone.pending,
        ],
      );
    },
  );

  testWidgets('metadata stays readable on light panels and dark headers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KodimaliTheme.mobileLight(),
        home: const Scaffold(
          body: Column(
            children: [
              ManagePanel(child: ManageMetaWrap(items: ['Available'])),
              ManageHeroCard(
                title: 'Dashboard',
                subtitle: 'Overview',
                bottom: ManageMetaWrap(items: ['Inquiries']),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final light = tester.widget<Text>(find.text('Available')).style!.color!;
    final dark = tester.widget<Text>(find.text('Inquiries')).style!.color!;
    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }

    expect(contrast(light, Colors.white), greaterThanOrEqualTo(4.5));
    expect(contrast(dark, KodimaliColors.navy), greaterThanOrEqualTo(4.5));
    expect(tester.takeException(), isNull);
  });

  test(
    'location duplicates, access denials and missing directory deployment have clear errors',
    () async {
      var code = '23505';
      final api = SupabaseClient(
        'https://fixture.invalid',
        'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({'code': code, 'message': 'fixture database error'}),
            code == '42501'
                ? 403
                : code == 'PGRST202'
                ? 404
                : 409,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
      );
      addTearDown(api.dispose);
      final repo = ManageRepository(api);
      await expectLater(
        repo.addLocation(
          name: 'Arusha',
          type: LocationType.region,
          parentId: 'country',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('already exists'),
          ),
        ),
      );
      code = '42501';
      await expectLater(
        repo.renameLocation(id: 'region', name: 'Renamed'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('access required'),
          ),
        ),
      );
      code = 'PGRST202';
      await expectLater(
        repo.fetchAdminCustomerUsers(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('update is required'),
          ),
        ),
      );
    },
  );

  testWidgets(
    'drawer loads only visited modules and Back returns to the previous module',
    (tester) async {
      final repo = FixtureLocations(client);
      final controller = AppController(repo);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, state) => const SizedBox.shrink()),
        ],
      );
      addTearDown(controller.dispose);
      addTearDown(router.dispose);
      var index = 0;
      var dashboardMounts = 0;
      var usersMounts = 0;
      await tester.pumpWidget(
        ManageLanguageScope(
          languageCode: 'en',
          onChanged: (_) async {},
          child: AppScope(
            dependencies: AppDependencies(
              repository: repo,
              controller: controller,
              router: router,
            ),
            child: MaterialApp(
              theme: KodimaliTheme.mobileLight(),
              home: StatefulBuilder(
                builder: (context, update) => ManageWorkspaceScaffold(
                  title: 'Manage',
                  currentIndex: index,
                  onSelect: (value) => update(() => index = value),
                  destinations: [
                    ManageWorkspaceDestination(
                      label: 'Dashboard',
                      icon: Icons.dashboard,
                      screen: ProbeScreen(onMount: () => dashboardMounts++),
                    ),
                    ManageWorkspaceDestination(
                      label: 'Users',
                      icon: Icons.people,
                      screen: ProbeScreen(onMount: () => usersMounts++),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(dashboardMounts, 1);
      expect(usersMounts, 0);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Users'));
      await tester.pumpAndSettle();
      expect(index, 1);
      expect(usersMounts, 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(index, 0);
      expect(dashboardMounts, 1);
      expect(usersMounts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 375.0, 390.0, 430.0]) {
    testWidgets(
      'customer directory searches beyond the first page and returns to its filter at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: KodimaliTheme.mobileLight(),
            home: Scaffold(body: UsersTab(repository: FixtureUsers(client))),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Customer 1'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Customer 45');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ListTile, 'Customer 45'), findsOneWidget);
        await tester.tap(find.widgetWithText(ListTile, 'Customer 45'));
        await tester.pumpAndSettle();
        expect(find.text('User details'), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Customer 45',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 375.0, 390.0, 430.0]) {
    testWidgets('location hierarchy and Back preserve context at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FixtureLocations(client);
      await tester.pumpWidget(
        MaterialApp(
          theme: KodimaliTheme.mobileLight(),
          home: Scaffold(body: LocationsTab(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      for (final name in ['Arusha', 'Arusha District', 'Sokoni']) {
        await tester.tap(find.widgetWithText(ListTile, name));
        await tester.pumpAndSettle();
      }
      expect(find.widgetWithText(ListTile, 'Central'), findsOneWidget);
      expect(repo.calls, ['country', 'region', 'district', 'ward']);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Sokoni'), findsOneWidget);
      expect(repo.calls.length, 4);
    });
  }
  testWidgets('add and rename use the selected parent and preserve its id', (
    tester,
  ) async {
    final repo = FixtureLocations(client);
    await tester.pumpWidget(
      MaterialApp(
        theme: KodimaliTheme.mobileLight(),
        home: Scaffold(
          body: LocationsTab(
            repository: repo,
            ancestors: repo.rows.take(2).toList(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.textContaining(RegExp('Add district', caseSensitive: false)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'New District');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.rows.last['parent_id'], 'region');
    expect(repo.rows.last['location_type'], 'district');
    final card = find.ancestor(
      of: find.text('New District'),
      matching: find.byType(Card),
    );
    final edit = find.descendant(
      of: card,
      matching: find.widgetWithText(OutlinedButton, 'Edit'),
    );
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(edit).onPressed, isNotNull);
    await tester.tap(edit.hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Renamed District');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.rows.last['id'], 'new');
    expect(repo.rows.last['parent_id'], 'region');
    expect(repo.rows.last['name'], 'Renamed District');
  });
  testWidgets('brand loader honors reduced motion and disposes immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: KodimaliLoading(label: 'Loading...'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
