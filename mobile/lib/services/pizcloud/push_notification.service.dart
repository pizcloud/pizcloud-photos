import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:immich_mobile/features/pizcloud/notifications/notification_api_client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService._();

  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Call this after user logged-in (have authToken).
  static Future<void> initAndRegister({required String baseUrl, required String authToken}) async {
    if (_initialized) return;
    _initialized = true;

    await Firebase.initializeApp();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // iOS permission
    final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

    // If user denies, you can stop here.
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    await _initLocalNotifications();

    // Listen foreground message -> show local notification
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Handle click when app opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // Register current token
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _registerToServer(baseUrl: baseUrl, authToken: authToken, fcmToken: token);
    }

    // Token refresh -> update server
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await _registerToServer(baseUrl: baseUrl, authToken: authToken, fcmToken: newToken);
    });
  }

  static Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@drawable/notification_icon');
    const ios = DarwinInitializationSettings();

    const init = InitializationSettings(android: android, iOS: ios);
    await _local.initialize(
      init,
      onDidReceiveNotificationResponse: (resp) {
        // Notification tapped while app in foreground/background (local notif).
        // You can parse payload & route.
      },
    );

    // Android channel (important for heads-up)
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
      payload: message.data.isNotEmpty ? message.data.toString() : null,
    );
  }

  static Future<void> _onMessageOpenedApp(RemoteMessage message) async {}

  static Future<void> _registerToServer({
    required String baseUrl,
    required String authToken,
    required String fcmToken,
  }) async {
    final deviceId = await _getDeviceId();
    final platform = Platform.isIOS ? 'ios' : 'android';

    final api = NotificationApiClient(baseUrl: baseUrl, authToken: authToken);
    await api.registerDevice(token: fcmToken, deviceId: deviceId, platform: platform);
  }

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
