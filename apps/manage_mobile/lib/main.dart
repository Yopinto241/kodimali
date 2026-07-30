import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_dependencies.dart';
import 'core/config/app_env.dart';
import 'core/notifications/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    AppEnv.ensureConfigured();

    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      publishableKey: AppEnv.supabasePublishableKey,
    );

    final AppDependencies dependencies = AppDependencies.create();

    runApp(ManageApp(dependencies: dependencies));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runBackgroundStartup(dependencies));
    });
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stackTrace),
    );
    runApp(_StartupErrorApp(message: error.toString()));
  }
}

Future<void> _runBackgroundStartup(AppDependencies dependencies) async {
  try {
    await dependencies.controller.initialize();
    await PushNotificationService.instance.initialize();
    PushNotificationService.instance.notificationTaps.listen((data) {
      final String route = data["route"]?.toString() ?? "";
      if (route.startsWith("chat/")) {
        dependencies.router.go("/listing-chat/${route.substring(5)}");
      }
    });
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stackTrace),
    );
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text(
                    "KODIMALI Agent could not start",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
