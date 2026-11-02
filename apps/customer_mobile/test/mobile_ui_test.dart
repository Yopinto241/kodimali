import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:customer_mobile/core/data/customer_account_repository.dart';
import 'package:customer_mobile/app.dart';
import 'package:customer_mobile/core/data/customer_public_repository.dart';
import 'package:customer_mobile/core/localization/customer_localization.dart';
import 'package:customer_mobile/features/account/customer_account_screens.dart';
import 'package:customer_mobile/features/events/events_marketplace_screen.dart';
import 'package:customer_mobile/features/navigation/customer_category_menu.dart';

Widget host(Widget child, String language, ThemeData theme, double scale) =>
    CustomerAppScope(
      languageCode: language,
      onLanguageChanged: (_) async {},
      themeMode: ThemeMode.system,
      onThemeModeChanged: (_) async {},
      child: MaterialApp(
        theme: theme,
        locale: Locale(language),
        supportedLocales: const [Locale('en'), Locale('sw')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: child,
      ),
    );

void main() {
  late SupabaseClient client;
  setUpAll(() {
    client = SupabaseClient(
      'https://fixture.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
  });
  tearDownAll(() => client.dispose());

  testWidgets(
    'Home header has accessible controls without narrow-screen overflow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        host(
          Scaffold(
            body: PublicHomeScreen(
              repository: CustomerPublicRepository(client),
              refreshTick: 0,
              regionId: null,
              districtId: null,
              wardId: null,
              areaId: null,
              latitude: null,
              longitude: null,
              bannerHidden: true,
              onUseGps: () async {},
              onChooseLocation: () async {},
              onSkipBanner: () async {},
              categoryMenuItems: const [
                {
                  'id': 'apartment-id',
                  'slug': 'apartment',
                  'name': 'Apartment',
                },
              ],
              onOpenCategoriesOverview: () {},
              onOpenCategory: (_) {},
            ),
          ),
          'sw',
          KodimaliTheme.mobileLight(),
          1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CustomerCategoryMenu), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.search_rounded).first);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration?.filled,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final language in ['sw', 'en']) {
    for (final dark in [false, true]) {
      testWidgets(
        'Events and login readable: $language, dark=$dark, narrow and enlarged text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final theme = dark
              ? KodimaliTheme.mobileDark()
              : KodimaliTheme.mobileLight();
          for (final size in [const Size(320, 800), const Size(390, 844)]) {
            tester.view.physicalSize = size;
            for (final scale in [1.0, 1.5]) {
              for (final screen in [
                EventsMarketplaceScreen(
                  repository: CustomerPublicRepository(client),
                ),
                CustomerAuthScreen(
                  repository: CustomerAccountRepository(client),
                ),
              ]) {
                await tester.pumpWidget(host(screen, language, theme, scale));
                await tester.pumpAndSettle();
                final title = find
                    .descendant(
                      of: find.byType(AppBar),
                      matching: find.byType(RichText),
                    )
                    .first;
                final paragraph = tester.renderObject<RenderParagraph>(title);
                final foreground = paragraph.text.style!.color!;
                final background = theme.appBarTheme.backgroundColor!;
                final a = foreground.computeLuminance();
                final b = background.computeLuminance();
                final contrast =
                    ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
                expect(contrast, greaterThanOrEqualTo(4.5));
                expect(
                  tester.takeException(),
                  isNull,
                  reason: '$size, $scale, ${screen.runtimeType}',
                );
                await tester.pumpWidget(const SizedBox());
              }
            }
          }
        },
      );
    }

    testWidgets(
      'Home category menu searches both languages and navigates after closing: $language',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        Map<String, dynamic>? chosen;
        var all = 0;
        await tester.pumpWidget(
          host(
            Scaffold(
              body: ColoredBox(
                color: KodimaliColors.navy,
                child: CustomerCategoryMenu(
                  categories: const [
                    {'id': 'house-id', 'slug': 'house', 'name': 'House'},
                    {
                      'id': 'apartment-id',
                      'slug': 'apartment',
                      'name': 'Apartment',
                    },
                  ],
                  onOpenAll: () => all++,
                  onOpenCategory: (category) => chosen = category,
                ),
              ),
            ),
            language,
            KodimaliTheme.mobileLight(),
            1.5,
          ),
        );
        final trigger = find.byType(OutlinedButton);
        expect(tester.getSize(trigger).height, greaterThanOrEqualTo(48));
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Apartment');
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ListTile, 'Apartment'), findsOneWidget);
        await tester.tap(find.widgetWithText(ListTile, 'Apartment'));
        await tester.pumpAndSettle();
        expect(chosen?['id'], 'apartment-id');
        expect(find.byType(TextField), findsNothing);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Nyumba');
        await tester.pumpAndSettle();
        expect(find.byType(ListTile), findsNWidgets(2));
        await tester.tap(find.byType(ListTile).first);
        await tester.pumpAndSettle();
        expect(all, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
