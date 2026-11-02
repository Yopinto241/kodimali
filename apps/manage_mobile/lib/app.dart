import 'package:flutter_core/localized_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_dependencies.dart';
import 'core/localization/manage_localization.dart';
import 'core/widgets/app_scope.dart';

class ManageApp extends StatefulWidget {
  const ManageApp({super.key, required this.dependencies});
  final AppDependencies dependencies;

  @override
  State<ManageApp> createState() => _ManageAppState();
}

class _ManageAppState extends State<ManageApp> {
  static const _preferenceKey = 'manage_language_code';
  String _languageCode = 'sw';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(
        () => _languageCode = prefs.getString(_preferenceKey) == 'en'
            ? 'en'
            : 'sw',
      );
    });
  }

  Future<void> _setLanguage(String value) async {
    final next = value == 'en' ? 'en' : 'sw';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferenceKey, next);
    if (mounted) setState(() => _languageCode = next);
  }

  @override
  Widget build(BuildContext context) {
    final light = KodimaliTheme.mobileLight();
    return ManageLanguageScope(
      languageCode: _languageCode,
      onChanged: _setLanguage,
      child: AppScope(
        dependencies: widget.dependencies,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: mobileUi(context, 'KODIMALI Manage'),
          locale: Locale(_languageCode),
          supportedLocales: const <Locale>[Locale('sw'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: light,
          darkTheme: KodimaliTheme.mobileDark(),
          themeMode: ThemeMode.system,
          routerConfig: widget.dependencies.router,
        ),
      ),
    );
  }
}
