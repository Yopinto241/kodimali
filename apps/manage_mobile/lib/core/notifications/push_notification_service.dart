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
  static final instance = PushNotificationService._();
  final _local = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get notificationTaps => _taps.stream;
  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload?.isNotEmpty == true) _taps.add({'route': r.payload});
      },
    );
    final a = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await a?.createNotificationChannel(
      const AndroidNotificationChannel(
        'kodimali_chat',
        'KODIMALI Chats',
        importance: Importance.high,
      ),
    );
    await a?.createNotificationChannel(
      const AndroidNotificationChannel(
        'kodimali_updates',
        'KODIMALI Updates',
        importance: Importance.high,
      ),
    );
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
    FirebaseMessaging.onMessage.listen(_show);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _taps.add(m.data));
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _taps.add(initial.data);
    FirebaseMessaging.instance.onTokenRefresh.listen(_register);
    Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => registerCurrentDevice(),
    );
    await registerCurrentDevice();
  }

  Future<void> _show(RemoteMessage m) async {
    final n = m.notification;
    if (n == null) return;
    final chat = (m.data['eventType']?.toString() ?? '').contains('chat');
    await _local.show(
      id: m.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          chat ? 'kodimali_chat' : 'kodimali_updates',
          chat ? 'KODIMALI Chats' : 'KODIMALI Updates',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: m.data['route']?.toString(),
    );
  }

  Future<void> registerCurrentDevice() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null) await _register(t);
    } catch (_) {}
  }

  Future<void> _register(String token) async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    String? id;
    final d = DeviceInfoPlugin();
    if (Platform.isAndroid) id = (await d.androidInfo).id;
    if (Platform.isIOS) id = (await d.iosInfo).identifierForVendor;
    await Supabase.instance.client.rpc(
      'register_push_device',
      params: {
        'p_token': token,
        'p_platform': Platform.operatingSystem,
        'p_app_surface': 'manage',
        'p_device_id': id,
        'p_locale': 'sw',
      },
    );
  }
}
