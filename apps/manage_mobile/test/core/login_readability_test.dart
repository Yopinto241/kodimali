import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:manage_mobile/core/data/manage_repository.dart';
import 'package:manage_mobile/core/config/app_dependencies.dart';
import 'package:manage_mobile/core/state/app_controller.dart';
import 'package:manage_mobile/core/widgets/app_scope.dart';
import 'package:manage_mobile/core/localization/manage_localization.dart';
import 'package:manage_mobile/features/auth/presentation/login_screen.dart';

class FailedLogin extends ManageRepository {
  FailedLogin(super.client);
  @override
  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    throw StateError('User already registered');
  }
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
  for (final dark in [false, true]) {
    for (final language in ['en', 'sw']) {
      testWidgets(
        'login message readable and persistent: $language dark=$dark',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repo = FailedLogin(client);
          final controller = AppController(repo);
          final router = GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
            ],
          );
          addTearDown(controller.dispose);
          addTearDown(router.dispose);
          final theme = dark
              ? KodimaliTheme.dark()
              : KodimaliTheme.mobileLight();
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
                  theme: theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.4)),
                    child: child!,
                  ),
                  home: const LoginScreen(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextFormField).first,
            'fixture@example.invalid',
          );
          await tester.enterText(
            find.byType(TextFormField).last,
            'test-password',
          );
          await tester.ensureVisible(find.byType(FilledButton));
          await tester.tap(find.byType(FilledButton));
          await tester.pumpAndSettle();
          final message = find.text(
            language == 'sw'
                ? 'Mtumiaji huyu amesajiliwa tayari'
                : 'User already registered',
          );
          expect(message, findsOneWidget);
          expect(message.hitTestable(), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 100));
          expect(message, findsOneWidget);
          expect(find.byType(SnackBar), findsNothing);
          final text = tester.widget<Text>(message);
          final foreground = text.style!.color!.computeLuminance();
          final banner = tester.widget<Container>(
            find.ancestor(of: message, matching: find.byType(Container)).first,
          );
          final background = (banner.decoration as BoxDecoration).color!
              .computeLuminance();
          final contrast = foreground > background
              ? (foreground + .05) / (background + .05)
              : (background + .05) / (foreground + .05);
          expect(contrast, greaterThanOrEqualTo(4.5));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
