import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_mobile/core/localization/customer_localization.dart';

void main() {
  testWidgets('customer keyed and new copy follow the same language setting', (
    tester,
  ) async {
    for (final code in ['sw', 'en', 'sw']) {
      await tester.pumpWidget(
        CustomerAppScope(
          languageCode: code,
          onLanguageChanged: (_) async {},
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) async {},
          child: MaterialApp(
            home: Builder(
              builder: (context) => Column(
                children: [
                  Text(context.tr('nav.account')),
                  Text(context.tr('Save alert')),
                  Text(context.tr('apartment.bookingTitle')),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text(code == 'sw' ? 'Akaunti' : 'Account'), findsOneWidget);
      expect(
        find.text(code == 'sw' ? 'Hifadhi arifa' : 'Save alert'),
        findsOneWidget,
      );
      expect(
        find.text(code == 'sw' ? 'Book apartment hii' : 'Book this apartment'),
        findsOneWidget,
      );
    }
  });
}
