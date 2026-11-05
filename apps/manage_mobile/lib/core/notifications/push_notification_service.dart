import 'package:flutter/widgets.dart';
import 'package:flutter_core/push_tap_inbox.dart';
import 'package:flutter_core/push_payload.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_core/push_device_lifecycle.dart';
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

class PushNotificationService with WidgetsBindingObserver {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final PushTapInbox _taps = PushTapInbox();
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<AuthState>? _authChanges;
  bool _initialized = false;
  Future<void>? _initializing;
  StreamSubscription<RemoteMessage>? _messages, _opened;
  Timer? _retryTimer;
  bool _observing = false;
  bool _registering = false;
  Stream<Map<String, dynamic>> get notificationTaps => _taps.stream;

  late final PushDeviceLifecycle deviceLifecycle = PushDeviceLifecycle(
    currentUser: () => Supabase.instance.client.auth.currentUser?.id,
    read: () async {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          jsonDecode(prefs.getString('push_devices_manage_v2') ?? '[]') as List;
      return raw.map((row) => Map<String, String>.from(row as Map)).toList();
    },
    write: (rows) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('push_devices_manage_v2', jsonEncode(rows));
    },
    unregister: (row) async {
      await Supabase.instance.client.rpc(
        'unregister_push_installation',
        params: {'p_token': row['token'], 'p_capability': row['capability']},
      );
    },
    register: (row) => _registerRecord(row),
  );
  Future<void> prepareLogout() async {
    await deviceLifecycle.disable();
    try {
      await FirebaseMessaging.instance.deleteToken().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {}
    try {
      await _local.cancelAll().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (_initialized) return;
    if (_initializing != null) return _initializing!;
    final attempt = _initialize();
    _initializing = attempt;
    try {
      await attempt;
      _initialized = true;
    } catch (_) {
      await _messages?.cancel();
      await _opened?.cancel();
      await _tokenRefresh?.cancel();
      await _authChanges?.cancel();
      _retryTimer?.cancel();
      _retryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed) {
          unawaited(_recover());
        }
      });
      rethrow;
    } finally {
      _initializing = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_recover());
  }

  Future<void> _recover() async {
    try {
      await initialize();
      await _registerWithRetry();
    } catch (error) {
      debugPrint(
        'Notification setup will retry on resume: ${error.runtimeType}',
      );
    }
  }

  Future<void> _initialize() async {
    await deviceLifecycle.flush();
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
          _taps.add(decodePushTap(payload));
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
          alert: false,
          badge: false,
          sound: false,
        );
    _messages = FirebaseMessaging.onMessage.listen(_showForeground);
    _opened = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _taps.add(message.data),
    );
    final localLaunch = await _local.getNotificationAppLaunchDetails();
    final localPayload = localLaunch?.notificationResponse?.payload;
    if (localLaunch?.didNotificationLaunchApp == true && localPayload != null) {
      _taps.add(decodePushTap(localPayload));
    }
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _taps.add(initial.data);
    _tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => unawaited(_registerWithRetry(token: token)),
    );
    _authChanges = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) => unawaited(
        state.session == null
            ? deviceLifecycle.disable()
            : _registerWithRetry(),
      ),
    );
    await _registerWithRetry();
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_registerWithRetry());
      }
    });
  }

  Future<void> _registerWithRetry({String? token}) async {
    if (_registering) return;
    _registering = true;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        if (Supabase.instance.client.auth.currentUser == null) return;
        try {
          if (token == null) {
            await registerCurrentDevice();
          } else {
            await _register(token);
          }
          return;
        } catch (_) {
          if (attempt < 2) {
            await Future<void>.delayed(Duration(seconds: attempt + 1));
          }
        }
      }
    } finally {
      _registering = false;
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    if (!pushBelongsToUser(
      message.data,
      Supabase.instance.client.auth.currentUser?.id,
    )) {
      return;
    }
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
      payload: jsonEncode(message.data),
    );
  }

  Future<void> registerCurrentDevice() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) throw StateError("Push token is not available yet");
    await _register(token);
  }

  Future<void> _register(String token) => deviceLifecycle.synchronize(token);

  Future<void> _registerRecord(DeviceRecord row) async {
    final token = row['token']!;
    if (Supabase.instance.client.auth.currentUser == null) return;
    String? id;
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) id = (await info.androidInfo).id;
    if (Platform.isIOS) id = (await info.iosInfo).identifierForVendor;
    await Supabase.instance.client.rpc(
      'register_push_device_v2',
      params: <String, dynamic>{
        'p_token': token,
        'p_unregister_capability': row['capability'],
        'p_platform': Platform.operatingSystem,
        'p_app_surface': 'manage',
        'p_device_id': id,
        'p_locale': 'sw',
      },
    );
  }

  Future<void> dispose() async {
    await _tokenRefresh?.cancel();
    await _authChanges?.cancel();
    await _messages?.cancel();
    await _opened?.cancel();
    _retryTimer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    await _taps.close();
  }
}
