import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as piz_persist;

class NotificationApiClient {
  NotificationApiClient({required this.baseUrl, required this.authToken});

  final String baseUrl;
  final String authToken;

  Future<void> registerDevice({
    required String token,
    required String deviceId,
    required String platform, // "android" | "ios"
    String? appVersion,
    String? locale,
    String? timeZone,
  }) async {
    // New Dio-based implementation using PersistCookieJar (sid) + headers
    final client = await piz_persist.ApiPersistCookieJarService.instance(
      baseUrl: baseUrl,
      // headers: {'Authorization': 'Bearer $authToken', 'Content-Type': 'application/json'},
    );
    final normalizedLocale = locale?.trim();
    final effectiveLocale = (normalizedLocale == null || normalizedLocale.isEmpty) ? 'en' : normalizedLocale;
    final normalizedTimeZone = timeZone?.trim();

    final res = await client.client.post<dynamic>(
      '/notifications/devices',
      data: {
        'token': token,
        'deviceId': deviceId,
        'platform': platform,
        'locale': effectiveLocale,
        if (normalizedTimeZone != null && normalizedTimeZone.isNotEmpty) 'timeZone': normalizedTimeZone,
        if (appVersion != null) 'appVersion': appVersion,
      },
      options: Options(extra: const <String, dynamic>{'clientEventName': 'notifications.device.register'}),
    );
    final status = res.statusCode ?? 0;
    debugPrint('res.statusCode: $status');
    if (status != 201 && status != 200) {
      throw Exception('Failed to register device: $status ${res.data}');
    }
  }

  Future<void> unregisterDevice({required String deviceId}) async {
    // Old http-based implementation (kept for reference)
    // final res = await http.delete(
    //   Uri.parse('$baseUrl/notifications/devices/$deviceId'),
    //   headers: {'Authorization': 'Bearer $authToken'},
    // );
    // if (res.statusCode != 200) {
    //   throw Exception('Failed to unregister device: ${res.statusCode} ${res.body}');
    // }

    // New Dio-based implementation using PersistCookieJar (sid) + headers
    final client = await piz_persist.ApiPersistCookieJarService.instance(
      baseUrl: baseUrl,
      // headers: {'Authorization': 'Bearer $authToken'},
    );
    final res = await client.client.delete<dynamic>(
      '/notifications/devices/$deviceId',
      options: Options(extra: const <String, dynamic>{'clientEventName': 'notifications.device.unregister'}),
    );
    final status = res.statusCode ?? 0;
    if (status != 200) {
      throw Exception('Failed to unregister device: $status ${res.data}');
    }
  }
}
