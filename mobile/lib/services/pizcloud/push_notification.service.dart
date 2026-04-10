import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

import 'package:immich_mobile/features/pizcloud/notifications/notification_api_client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

typedef PushNotificationTapHandler = FutureOr<void> Function(Map<String, dynamic> data);

class PushNotificationService {
  PushNotificationService._();

  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  static bool _firebaseReady = false;
  // static bool _initialized = false;

  static String? _baseUrl;
  static String? _authToken;
  static PushNotificationTapHandler? _tapHandler;
  static bool _didHandleInitialMessage = false;

  static StreamSubscription<RemoteMessage>? _onMessageSub;
  static StreamSubscription<RemoteMessage>? _onOpenSub;
  static StreamSubscription<String>? _onTokenRefreshSub;

  static void setTapHandler(PushNotificationTapHandler? handler) {
    _tapHandler = handler;
  }

  /// Call this after user logged-in (have authToken).
  static Future<void> initAndRegister({required String baseUrl, required String authToken}) async {
    _baseUrl = baseUrl;
    _authToken = authToken;

    await _ensureFirebaseInitialized();
    await _handleInitialMessageIfAny();

    await _registerWithRetry();
  }

  static Future<void> onLogout() async {
    _authToken = null;
    _baseUrl = null;
  }

  static Future<void> _ensureFirebaseInitialized() async {
    if (_firebaseReady) return;
    _firebaseReady = true;

    await Firebase.initializeApp();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Request permission (iOS required; Android 13+ also)
    final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      // Permission denied -> cannot show push. Still keep firebaseReady true to avoid re-init loops.
      return;
    }

    await _initLocalNotifications();

    await _onMessageSub?.cancel();
    await _onOpenSub?.cancel();
    await _onTokenRefreshSub?.cancel();

    _onMessageSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    _onOpenSub = FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
    _onTokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await _registerTokenToServer(newToken);
    });
  }

  static Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@drawable/notification_icon');
    const ios = DarwinInitializationSettings();

    const init = InitializationSettings(android: android, iOS: ios);
    await _local.initialize(
      init,
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload == null || payload.isEmpty) {
          return;
        }

        final data = _decodePayloadMap(payload);
        if (data == null) {
          return;
        }

        unawaited(_dispatchNotificationTap(data));
      },
    );

    const channel = AndroidNotificationChannel(
      'quota_alerts',
      'Quota Alerts',
      description: 'Notifications about storage/quota usage',
      importance: Importance.high,
    );

    final androidPlugin = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(channel);
  }

  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    // FlutterFire: in foreground, SDK won't show system notification by default. :contentReference[oaicite:6]{index=6}
    final notif = message.notification;
    if (notif == null) return;

    await _local.show(
      notif.hashCode,
      notif.title,
      notif.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'quota_alerts',
          'Quota Alerts',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
    );
  }

  static Future<void> _onMessageOpenedApp(RemoteMessage message) async {
    await _dispatchNotificationTap(message.data);
  }

  static Future<void> _handleInitialMessageIfAny() async {
    if (_didHandleInitialMessage) {
      return;
    }
    _didHandleInitialMessage = true;

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage == null) {
      return;
    }

    await _dispatchNotificationTap(initialMessage.data);
  }

  static Map<String, dynamic>? _decodePayloadMap(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return null;
      }

      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _dispatchNotificationTap(Map<String, dynamic> data) async {
    if (data.isEmpty) {
      return;
    }

    final handler = _tapHandler;
    if (handler == null) {
      return;
    }

    await handler(data);
  }

  static Future<void> _registerWithRetry() async {
    if (_baseUrl == null || _authToken == null) return;

    // iOS: sometimes APNs token not ready immediately
    if (Platform.isIOS) {
      // Not required but helps timing in real devices
      await FirebaseMessaging.instance.getAPNSToken();
    }

    const maxAttempts = 6;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final token = await FirebaseMessaging.instance.getToken();

        if (token != null && token.isNotEmpty) {
          await _registerTokenToServer(token);
          return; // success
        }
      } catch (_) {
        // ignore and retry
      }

      // Backoff: 300ms, 600ms, 900ms...
      await Future.delayed(Duration(milliseconds: 300 * attempt));
    }

    // If still null, do nothing. Token refresh listener may fire later and register.
  }

  static Future<void> _registerTokenToServer(String fcmToken, {String? locale}) async {
    final baseUrl = _baseUrl;
    final authToken = _authToken;
    if (baseUrl == null || authToken == null) return;

    final deviceId = await _getDeviceId();
    final platform = Platform.isIOS ? 'ios' : 'android';

    final api = NotificationApiClient(baseUrl: baseUrl, authToken: authToken);

    try {
      await api.registerDevice(
        token: fcmToken,
        deviceId: deviceId,
        platform: platform,
        locale: _resolveLocaleTag(locale),
      );
    } catch (e) {
      rethrow;
    }
  }

  static String _resolveLocaleTag([String? locale]) {
    final raw = (locale ?? Intl.defaultLocale ?? '').trim();
    if (raw.isEmpty) {
      return 'en';
    }
    return raw.replaceAll('_', '-');
  }

  static Future<void> syncDeviceLocale({String? locale}) async {
    if (_baseUrl == null || _authToken == null) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      await _registerTokenToServer(token, locale: locale);
    } catch (_) {
      // Best-effort sync
    }
  }

  // static Future<void> _registerToServer({
  //   required String baseUrl,
  //   required String authToken,
  //   required String fcmToken,
  // }) async {
  //   final deviceId = await _getDeviceId();
  //   final platform = Platform.isIOS ? 'ios' : 'android';

  //   final api = NotificationApiClient(baseUrl: baseUrl, authToken: authToken);
  //   await api.registerDevice(token: fcmToken, deviceId: deviceId, platform: platform);
  // }

  static Future<String> _getDeviceId() async {
    final info = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final ios = await info.iosInfo;
      // identifierForVendor may be null on rare cases -> fallback
      return ios.identifierForVendor ?? 'ios-unknown';
    }
    final android = await info.androidInfo;
    // "id" is not guaranteed stable forever, but good enough for token mapping
    return android.id;
  }
}
