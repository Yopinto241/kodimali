import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

import 'core/config/app_dependencies.dart';
import 'core/widgets/app_scope.dart';

class ManageApp extends StatelessWidget {
  const ManageApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: dependencies,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'KODIMALI Manage',
        theme: KodimaliTheme.light(),
        darkTheme: KodimaliTheme.dark(),
        themeMode: ThemeMode.system,
        routerConfig: dependencies.router,
      ),
    );
  }
}
