import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manage_mobile/core/localization/manage_localization.dart';

void main() {
  testWidgets('management copy follows the selected language', (tester) async {
    for (final code in ['sw', 'en', 'sw']) {
      await tester.pumpWidget(
        ManageLanguageScope(
          languageCode: code,
          onChanged: (_) async {},
          child: MaterialApp(
            home: Builder(builder: (context) => Text(context.tr('Save roles'))),
          ),
        ),
      );
      expect(
        find.text(code == 'sw' ? 'Hifadhi majukumu' : 'Save roles'),
        findsOneWidget,
      );
    }
  });
}
