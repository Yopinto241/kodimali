import 'package:flutter/widgets.dart';

import '../config/app_dependencies.dart';

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.dependencies, required super.child});

  final AppDependencies dependencies;

  static AppDependencies of(BuildContext context) {
    final AppScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppScope>();
    if (scope == null) {
      throw StateError("AppScope not found in widget tree");
    }
    return scope.dependencies;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    return oldWidget.dependencies != dependencies;
  }
}
