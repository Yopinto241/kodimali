import 'package:flutter/material.dart';
import 'package:flutter_core/localized_ui.dart';
import 'package:flutter_core/src/ui_copy.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog keeps required English terms in translated sentences', () {
    for (final entry in uiCopy.entries) {
      for (final word in ['apartment', 'book', 'booking']) {
        final pattern = RegExp('\\b$word\\b', caseSensitive: false);
        if (pattern.hasMatch(entry.key)) {
          expect(pattern.hasMatch(entry.value), isTrue, reason: entry.key);
        }
      }
    }
    expect(translateMobileUi('en', 'Listing imehifadhiwa.'), 'Listing saved.');
    expect(translateMobileUi('sw', 'Save promotion'), 'Hifadhi promosheni');
  });
  test(
    'copy translates in both directions without rewriting original content',
    () {
      expect(translateMobileUi('sw', 'Save'), 'Hifadhi');
      expect(translateMobileUi('en', 'Hifadhi'), 'Save');
      expect(translateMobileUi('sw', 'Bedrooms *'), 'Vyumba vya kulala *');
      expect(translateMobileUi('sw', 'acre'), 'ekari');
      for (final term in [
        'apartment',
        'Apartment',
        'book',
        'Book',
        'booking',
        'Booking',
      ]) {
        for (final language in ['en', 'sw']) {
          expect(translateMobileUi(language, term), term);
        }
      }
      for (final language in ['en', 'sw']) {
        expect(
          translateMobileUi(language, 'Amina apartment book booking'),
          'Amina apartment book booking',
        );
        expect(translateMobileUi(language, '255712345678'), '255712345678');
        expect(
          translateMobileUi(language, 'custom_category_id'),
          'custom_category_id',
        );
      }
    },
  );

  testWidgets(
    'locale changes update const labels and preserve inputs and option values',
    (tester) async {
      final language = ValueNotifier<String>('sw');
      final controller = TextEditingController(
        text: 'Amina apartment book booking',
      );
      addTearDown(language.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<String>(
          valueListenable: language,
          builder: (_, code, _) => MaterialApp(
            locale: Locale(code),
            supportedLocales: const [Locale('sw'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: Column(
                children: [
                  const LocalizedUiText('Save'),
                  Builder(
                    builder: (context) => Text(
                      mobileUiFormat(context, 'Payment: {0} · {1}', [
                        'Amina {1} book',
                        12000,
                      ]),
                    ),
                  ),
                  TextField(controller: controller),
                  DropdownButton<String>(
                    value: 'acre',
                    onChanged: (_) {},
                    items: const [
                      DropdownMenuItem(
                        value: 'acre',
                        child: LocalizedUiText('acre'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Hifadhi'), findsOneWidget);
      expect(find.text('Malipo: Amina {1} book · 12000'), findsOneWidget);
      expect(find.text('ekari'), findsOneWidget);
      language.value = 'en';
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Payment: Amina {1} book · 12000'), findsOneWidget);
      expect(find.text('acre'), findsOneWidget);
      expect(controller.text, 'Amina apartment book booking');
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        'acre',
      );
      language.value = 'sw';
      await tester.pumpAndSettle();
      expect(find.text('Hifadhi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
