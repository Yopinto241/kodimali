import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _taps =
      StreamController.broadcast();
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<AuthState>? _authChanges;
  bool _initialized = false;
  Stream<Map<String, dynamic>> get notificationTaps => _taps.stream;

  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_initialized) return;
    _initialized = true;
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload case final String payload
            when payload.isNotEmpty) {
          _taps.add(<String, dynamic>{'route': payload});
        }
      },
    );
    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'kodimali_chat',
        'KODIMALI Chats',
        description: 'Private customer and agent chat messages',
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'kodimali_updates',
        'KODIMALI Updates',
        description: 'Bookings, listings, payments and account updates',
        importance: Importance.high,
      ),
    );
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _taps.add(message.data),
    );
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _taps.add(initial.data);
    _tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => _register(token),
    );
    _authChanges = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => unawaited(_registerWithRetry()),
    );
    await _registerWithRetry();
  }

  Future<void> _registerWithRetry() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (Supabase.instance.client.auth.currentUser == null) return;
      try {
        await registerCurrentDevice();
        return;
      } catch (_) {
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final isChat = (message.data['eventType']?.toString() ?? '').contains(
      'chat',
    );
    await _local.show(
      id: message.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          isChat ? 'kodimali_chat' : 'kodimali_updates',
          isChat ? 'KODIMALI Chats' : 'KODIMALI Updates',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data['route']?.toString(),
    );
  }

  Future<void> registerCurrentDevice() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _register(token);
  }

  Future<void> _register(String token) async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    String? id;
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) id = (await info.androidInfo).id;
    if (Platform.isIOS) id = (await info.iosInfo).identifierForVendor;
    await Supabase.instance.client.rpc(
      'register_push_device',
      params: <String, dynamic>{
        'p_token': token,
        'p_platform': Platform.operatingSystem,
        'p_app_surface': 'customer',
        'p_device_id': id,
        'p_locale': 'sw',
      },
    );
  }

  Future<void> dispose() async {
    await _tokenRefresh?.cancel();
    await _authChanges?.cancel();
    await _taps.close();
  }
}
