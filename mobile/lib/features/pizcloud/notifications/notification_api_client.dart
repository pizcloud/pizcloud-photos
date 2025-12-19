import 'dart:convert';
import 'package:http/http.dart' as http;

class NotificationApiClient {
  NotificationApiClient({required this.baseUrl, required this.authToken});

  final String baseUrl;
  final String authToken;

  Future<void> registerDevice({
    required String token,
    required String deviceId,
    required String platform, // "android" | "ios"
    String? appVersion,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/notifications/devices'),
      headers: {'Authorization': 'Bearer $authToken', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'token': token,
        'deviceId': deviceId,
        'platform': platform,
        if (appVersion != null) 'appVersion': appVersion,
      }),
    );

    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception('Failed to register device: ${res.statusCode} ${res.body}');
    }
  }

  Future<void> unregisterDevice({required String deviceId}) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/notifications/devices/$deviceId'),
      headers: {'Authorization': 'Bearer $authToken'},
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to unregister device: ${res.statusCode} ${res.body}');
    }
  }
}
