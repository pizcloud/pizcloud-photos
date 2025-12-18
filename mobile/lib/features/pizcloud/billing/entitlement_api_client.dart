// lib/features/billing/entitlement_api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/domain/models/user.model.dart';

import 'package:immich_mobile/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:immich_mobile/services/pizcloud/auth_header.service.dart';

final String pizCloudServerUrl = AppConfig.pizCloudServerUrl.trim();

class EntitlementApiClient {
  EntitlementApiClient({required this.immichBaseUrl, required this.userEntity});

  final String immichBaseUrl;
  final UserDto userEntity;
  final authHeaders = const AuthHeaderService();
  // final String billingBaseUrl;

  String _join(String base, String path) {
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (path.startsWith('/')) path = path.substring(1);
    return '$base/$path';
  }

  Future<Map<String, dynamic>?> getEntitlements() async {
    final url = _join(immichBaseUrl, 'billing/entitlements');
    final oHeaders = authHeaders.authOnly();
    final res = await http.get(Uri.parse(url), headers: oHeaders);
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    return null;
  }

  Future<Map<String, dynamic>> getUsage() async {
    final url = _join(immichBaseUrl, 'billing/usage');
    final oHeaders = authHeaders.authOnly();

    final res = await http.get(Uri.parse(url), headers: oHeaders);
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    if (res.statusCode == 404) {
      return {'used_gb': 0, 'limit_gb': 0, 'percent': 0, 'state': 'ok'};
    }
    throw Exception('Failed to load usage: ${res.statusCode}');
  }

  Future<Map<String, dynamic>?> getReferralSummary() async {
    String path = 'papi/referral/summary';
    // String email = userEntity.email;
    // if (email != '' && email.trim().isNotEmpty) {
    //   final encoded = Uri.encodeQueryComponent(email.trim());
    //   path = '$path?email=$encoded';
    // }

    final jsonHeaders = authHeaders.authJson();
    final url = _join(pizCloudServerUrl, path);
    final res = await http.get(Uri.parse(url), headers: jsonHeaders);

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }

    debugPrint('getReferralSummary failed: ${res.statusCode} ${res.body}');
    return null;
  }

  Future<void> verifyIosReceipt({required String productId, required String receiptBase64}) async {
    final url = _join(pizCloudServerUrl, 'iap/ios/verify');
    final jsonHeaders = authHeaders.authJson();
    final res = await http.post(
      Uri.parse(url),
      headers: jsonHeaders,
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
    final url = _join(pizCloudServerUrl, 'iap/android/verify');
    final jsonHeaders = authHeaders.authJson();
    final res = await http.post(
      Uri.parse(url),
      headers: jsonHeaders,
      body: jsonEncode({'productId': productId, 'purchaseToken': purchaseToken, 'packageName': packageName}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Android verify failed: ${res.statusCode} ${res.body}');
    }
  }

  Future<void> notifyVerifiedPurchase({
    required String productId,
    required String platform, // 'android' | 'ios'
  }) async {
    final url = _join(pizCloudServerUrl, 'papi/billing/verify-success');
    final jsonHeaders = authHeaders.authJson();
    final res = await http.post(
      Uri.parse(url),
      headers: jsonHeaders,
      body: jsonEncode({'productId': productId, 'platform': platform}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Notify verified purchase failed: ${res.statusCode} ${res.body}');
    }
  }
}
