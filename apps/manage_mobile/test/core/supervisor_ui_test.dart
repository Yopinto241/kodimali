import 'package:manage_mobile/core/widgets/location_directory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:manage_mobile/core/data/manage_repository.dart';
import 'package:manage_mobile/core/config/app_dependencies.dart';
import 'package:manage_mobile/core/state/app_controller.dart';
import 'package:manage_mobile/core/widgets/app_scope.dart';
import 'package:manage_mobile/core/localization/manage_localization.dart';
import 'package:manage_mobile/features/admin/presentation/supervisor_management_screen.dart';
import 'package:manage_mobile/features/admin/presentation/agent_verification_tab.dart';
import 'manage_locations_ui_test.dart' as fixtures;

class SupervisorFixture extends fixtures.FixtureLocations {
  SupervisorFixture(super.client);
  final configured = <List<Object>>[];
  final transfers = <String?>[];
  String? assigned = 'supervisor-a';
  @override
  Future<List<JsonMap>> fetchSupervisorDirectory() async => [
    {
      'supervisor_id': 'supervisor-a',
      'full_name': 'Supervisor A',
      'account_email': 'supervisor@example.invalid',
      'location_id': 'region',
      'location_name': 'Arusha',
      'is_active': true,
      'agent_count': 1,
    },
    {
      'supervisor_id': 'supervisor-b',
      'full_name': 'Supervisor B',
      'account_email': 'other@example.invalid',
      'location_id': 'region',
      'location_name': 'Arusha',
      'is_active': true,
      'agent_count': 0,
    },
  ];
  @override
  Future<void> configureSupervisorTerritory(
    String email,
    String locationId,
    bool active,
  ) async {
    configured.add([email, locationId, active]);
  }

  @override
  Future<String?> fetchAgentSupervisor(String agentId) async => assigned;
  @override
  Future<void> assignAgentSupervisor(
    String agentId,
    String? supervisorId,
  ) async {
    assigned = supervisorId;
    transfers.add(supervisorId);
  }

  @override
  Future<JsonMap> fetchMySupervisorContext() async => {
    'scoped': true,
    'active': false,
  };
  @override
  Future<JsonMap> fetchAdminAgents({
    String? directoryLocationId,
    String searchText = '',
    String? accountStatus,
    String? verificationStatus,
    int limit = 40,
    int offset = 0,
  }) async => {'items': <JsonMap>[], 'total_count': 0};
}

void main() {
  late SupabaseClient client;
  setUp(() {
    client = SupabaseClient(
      'https://fixture.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDown(() => client.dispose());
  Future<void> pump(
    WidgetTester tester,
    SupervisorFixture repo,
    Widget child,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(repo);
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink())],
    );
    addTearDown(controller.dispose);
    addTearDown(router.dispose);
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
          child: MaterialApp(theme: KodimaliTheme.mobileLight(), home: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Super Admin assigns a regional supervisor from the mobile form',
    (tester) async {
      final repo = SupervisorFixture(client);
      await pump(tester, repo, const SupervisorManagementScreen());
      expect(find.text('Registered agent email'), findsOneWidget);
      expect(
        find.textContaining('Register as an agent first.'),
        findsOneWidget,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tanzania').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arusha').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'supervisor@example.invalid',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Assign supervisor territory'));
      await tester.tap(find.text('Assign supervisor territory'));
      await tester.pumpAndSettle();
      expect(repo.configured.single, [
        'supervisor@example.invalid',
        'region',
        true,
      ]);
      expect(find.text('Supervisor territory saved.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Super Admin transfers one agent to a different supervisor', (
    tester,
  ) async {
    final repo = SupervisorFixture(client);
    var saved = 0;
    await pump(
      tester,
      repo,
      Scaffold(
        body: AgentSupervisorAssignment(
          agentId: 'agent-a',
          onSaved: () async {
            saved++;
          },
        ),
      ),
    );
    await tester.tap(find.text('Assigned supervisor'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supervisor B · Arusha').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save agent team'));
    await tester.pumpAndSettle();
    expect(repo.transfers, ['supervisor-b']);
    expect(saved, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Supervisor without an active territory cannot create or take existing agents',
    (tester) async {
      final repo = SupervisorFixture(client);
      await pump(
        tester,
        repo,
        const Scaffold(body: AgentVerificationTab(scopedSupervisor: true)),
      );
      expect(
        find.text(
          'Ask Super Admin to activate your supervisor territory before adding agents.',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, 'Create account'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Create account'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Add agent'), findsNothing);
      expect(find.text('Supervisors and territories'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'location directory supports region and ward result scopes with breadcrumbs',
    (tester) async {
      final repo = SupervisorFixture(client);
      final views = <JsonMap?>[];
      await pump(
        tester,
        repo,
        Scaffold(
          body: SingleChildScrollView(
            child: LocationDirectory(onView: views.add),
          ),
        ),
      );
      expect(find.widgetWithText(ListTile, 'Arusha'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Arusha'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'View listings here'));
      expect(views.last?['id'], 'region');
      await tester.tap(find.widgetWithText(ListTile, 'Arusha District'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Sokoni'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'View listings here'));
      expect(views.last?['id'], 'ward');
      await tester.tap(find.widgetWithText(TextButton, 'Arusha'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Arusha District'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
