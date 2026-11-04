import 'package:flutter_core/push_payload.dart';
import 'core/router/notification_destination.dart';
import 'package:flutter_core/user_messages.dart';
import 'package:flutter_core/localized_ui.dart';
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
    runApp(_StartupErrorApp(message: safeUserMessage(error)));
  }
}

Future<void> _runBackgroundStartup(AppDependencies dependencies) async {
  try {
    await dependencies.controller.initialize();
    Map<String, dynamic>? pending;
    Future<void> open(Map<String, dynamic> data) async {
      pending = data;
      if (!dependencies.controller.isSignedIn) return;
      await dependencies.controller.refreshProfile();
      final next = pending;
      if (next == null || !dependencies.controller.isSignedIn) return;
      pending = null;
      if (!pushBelongsToUser(
        next,
        Supabase.instance.client.auth.currentUser?.id,
      )) {
        return;
      }
      dependencies.router.go(notificationDestination(next));
    }

    PushNotificationService.instance.notificationTaps.listen(open);
    Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.session != null && pending != null) unawaited(open(pending!));
    });
    await PushNotificationService.instance.initialize();
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
                  const LocalizedUiText(
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
