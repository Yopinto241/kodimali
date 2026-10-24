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
      setState(() => _languageCode = prefs.getString(_preferenceKey) == 'en' ? 'en' : 'sw');
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
    final light = KodimaliTheme.light();
    return ManageLanguageScope(
      languageCode: _languageCode,
      onChanged: _setLanguage,
      child: AppScope(
        dependencies: widget.dependencies,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'KODIMALI Manage',
          locale: Locale(_languageCode),
          supportedLocales: const <Locale>[Locale('sw'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: light.copyWith(
            splashFactory: InkSparkle.splashFactory,
            splashColor: KodimaliColors.green.withValues(alpha: 0.22),
            highlightColor: KodimaliColors.blueSurface.withValues(alpha: 0.10),
            scaffoldBackgroundColor: KodimaliColors.background,
            cardTheme: light.cardTheme.copyWith(color: KodimaliColors.lightSurface, shadowColor: const Color(0x290B1F3A)),
            appBarTheme: light.appBarTheme.copyWith(backgroundColor: const Color(0xFF0B1F3A), foregroundColor: Colors.white),
            navigationBarTheme: light.navigationBarTheme.copyWith(
              backgroundColor: const Color(0xFF102847), indicatorColor: const Color(0xFFA8D62A),
              labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(color: states.contains(WidgetState.selected) ? Colors.white : const Color(0xFFB5C1D1), fontWeight: FontWeight.w700)),
              iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(color: states.contains(WidgetState.selected) ? const Color(0xFF0B1F3A) : const Color(0xFFB5C1D1))),
            ),
          ),
          darkTheme: KodimaliTheme.dark().copyWith(
            splashFactory: InkSparkle.splashFactory,
            splashColor: KodimaliColors.green.withValues(alpha: 0.20),
            highlightColor: Colors.white.withValues(alpha: 0.06),
          ),
          themeMode: ThemeMode.system,
          routerConfig: widget.dependencies.router,
        ),
      ),
    );
  }
}
