import 'package:flutter/material.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as pizPersist;

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
  }) async {
    debugPrint('registerDevice-baseUrl: $baseUrl');
    // Old http-based implementation (kept for reference)
    // final res = await http.post(
    //   Uri.parse('$baseUrl/notifications/devices'),
    //   headers: {'Authorization': 'Bearer $authToken', 'Content-Type': 'application/json'},
    //   body: jsonEncode({
    //     'token': token,
    //     'deviceId': deviceId,
    //     'platform': platform,
    //     if (appVersion != null) 'appVersion': appVersion,
    //   }),
    // );
    // debugPrint('res.statusCode: ${res.statusCode}');
    // if (res.statusCode != 201 && res.statusCode != 200) {
    //   throw Exception('Failed to register device: ${res.statusCode} ${res.body}');
    // }

    // New Dio-based implementation using PersistCookieJar (sid) + headers
    final client = await pizPersist.ApiPersistCookieJarService.instance(
      baseUrl: baseUrl,
      // headers: {'Authorization': 'Bearer $authToken', 'Content-Type': 'application/json'},
    );
    final normalizedLocale = locale?.trim();
    final effectiveLocale = (normalizedLocale == null || normalizedLocale.isEmpty) ? 'en' : normalizedLocale;

    final res = await client.client.post<dynamic>(
      '/notifications/devices',
      data: {
        'token': token,
        'deviceId': deviceId,
        'platform': platform,
        'locale': effectiveLocale,
        if (appVersion != null) 'appVersion': appVersion,
      },
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
    final client = await pizPersist.ApiPersistCookieJarService.instance(
      baseUrl: baseUrl,
      // headers: {'Authorization': 'Bearer $authToken'},
    );
    final res = await client.client.delete<dynamic>('/notifications/devices/$deviceId');
    final status = res.statusCode ?? 0;
    if (status != 200) {
      throw Exception('Failed to unregister device: $status ${res.data}');
    }
  }
}
