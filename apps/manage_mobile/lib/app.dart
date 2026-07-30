import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

import 'core/config/app_dependencies.dart';
import 'core/widgets/app_scope.dart';

class ManageApp extends StatelessWidget {
  const ManageApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    final light = KodimaliTheme.light();
    return AppScope(
      dependencies: dependencies,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'KODIMALI Manage',
        theme: light.copyWith(
          scaffoldBackgroundColor: const Color(0xFFEAF1F8),
          cardTheme: light.cardTheme.copyWith(
            color: const Color(0xFFF4F8FC),
            shadowColor: const Color(0x290B1F3A),
          ),
          appBarTheme: light.appBarTheme.copyWith(
            backgroundColor: const Color(0xFF0B1F3A),
            foregroundColor: Colors.white,
          ),
          navigationBarTheme: light.navigationBarTheme.copyWith(
            backgroundColor: const Color(0xFF102847),
            indicatorColor: const Color(0xFFA8D62A),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                color: states.contains(WidgetState.selected)
                    ? Colors.white
                    : const Color(0xFFB5C1D1),
                fontWeight: FontWeight.w700,
              ),
            ),
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(
                color: states.contains(WidgetState.selected)
                    ? const Color(0xFF0B1F3A)
                    : const Color(0xFFB5C1D1),
              ),
            ),
          ),
        ),
        darkTheme: KodimaliTheme.dark(),
        themeMode: ThemeMode.system,
        routerConfig: dependencies.router,
      ),
    );
  }
}
