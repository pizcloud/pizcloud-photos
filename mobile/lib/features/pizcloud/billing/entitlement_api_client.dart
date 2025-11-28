// lib/features/billing/entitlement_api_client.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';

class EntitlementApiClient {
  EntitlementApiClient({required this.immichBaseUrl});

  final String immichBaseUrl;
  // final String billingBaseUrl;

  String _join(String base, String path) {
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (path.startsWith('/')) path = path.substring(1);
    return '$base/$path';
  }

  Map<String, String> _buildAuthHeaders({bool json = false}) {
    final headers = Map<String, String>.from(ApiService.getRequestHeaders());

    headers['Accept'] = 'application/json';

    final token = Store.tryGet(StoreKey.accessToken);
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';

      headers['x-immich-user-token'] = headers['x-immich-user-token'] ?? token;
    }

    if (json) {
      headers['Content-Type'] = 'application/json';
    }

    return headers;
  }

  Map<String, String> _authOnly() => _buildAuthHeaders(json: false);
  Map<String, String> _authJson() => _buildAuthHeaders(json: true);

  Future<Map<String, dynamic>?> getEntitlements() async {
    final url = _join(immichBaseUrl, 'billing/entitlements');
    final res = await http.get(Uri.parse(url), headers: _authOnly());
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    return null;
  }

  Future<Map<String, dynamic>> getUsage() async {
    final url = _join(immichBaseUrl, 'billing/usage');
    final h = _authOnly();

    final res = await http.get(Uri.parse(url), headers: h);
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    if (res.statusCode == 404) {
      return {'used_gb': 0, 'limit_gb': 0, 'percent': 0, 'state': 'ok'};
    }
    throw Exception('Failed to load usage: ${res.statusCode}');
  }

  Future<void> verifyIosReceipt({required String productId, required String receiptBase64}) async {
    final url = _join(immichBaseUrl, 'iap/ios/verify');
    final res = await http.post(
      Uri.parse(url),
      headers: _authJson(),
      body: jsonEncode({'productId': productId, 'receiptData': receiptBase64}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('iOS verify failed: ${res.statusCode} ${res.body}');
    }
  }

  Future<void> verifyAndroidPurchase({
    required String productId,
    required String purchaseToken,
    required String packageName,
  }) async {
    final url = _join(immichBaseUrl, 'iap/android/verify');
    final res = await http.post(
      Uri.parse(url),
      headers: _authJson(),
      body: jsonEncode({'productId': productId, 'purchaseToken': purchaseToken, 'packageName': packageName}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Android verify failed: ${res.statusCode} ${res.body}');
    }
  }
}
