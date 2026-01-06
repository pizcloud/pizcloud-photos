// lib/features/billing/entitlement_api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/domain/models/user.model.dart';

import 'package:immich_mobile/services/pizcloud/auth_header.service.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as pizPersist;
import 'package:immich_mobile/services/pizcloud/pizcloud_base_url.service.dart';

// final String pizCloudServerUrl = AppConfig.pizCloudServerUrl.trim(); // deprecated

class EntitlementApiClient {
  EntitlementApiClient({required this.immichBaseUrl, required this.userEntity});

  final String immichBaseUrl;
  final UserDto userEntity;
  final authHeaders = const AuthHeaderService();
  final PizcloudBaseUrlService _baseUrlService = PizcloudBaseUrlService();
  late final Future<pizPersist.ApiPersistCookieJarService> _pizApiService = _initPizApiService();
  // final String billingBaseUrl;

  Future<pizPersist.ApiPersistCookieJarService> _initPizApiService() async {
    final baseUrl = await _baseUrlService.resolveBaseUrl();
    return pizPersist.ApiPersistCookieJarService.instance(baseUrl: baseUrl);
  }

  String _join(String base, String path) {
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (path.startsWith('/')) path = path.substring(1);
    return '$base/$path';
  }

  Future<Map<String, dynamic>?> getEntitlements() async {
    final url = _join(immichBaseUrl, 'billing/entitlements');
    final oHeaders = authHeaders.authOnly();
    final res = await http.get(Uri.parse(url), headers: oHeaders);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return null;
    }

    if (res.statusCode == 204 || res.body.isEmpty || res.body == 'null') {
      return null;
    }

    final json = jsonDecode(res.body);
    return json is Map<String, dynamic> ? json : null;
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
    String path = 'referral/summary';
    final api = await _pizApiService;
    final res = await api.client.get<dynamic>('/$path');

    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final data = res.data;
      if (data is Map<String, dynamic>) {
        final wrapped = data['data'];
        if (wrapped is Map<String, dynamic>) return wrapped;
        return data;
      }
      try {
        if (data is String) {
          final decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic>) {
            final wrapped = decoded['data'];
            if (wrapped is Map<String, dynamic>) return wrapped;
            return decoded;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  Future<void> verifyIosReceipt({required String productId, required String receiptBase64}) async {
    // New Dio-based implementation using shared CookieJar (sid) + headers
    final api = await _pizApiService;
    final res = await api.client.post<dynamic>(
      '/billing/iap/ios/verify',
      data: {'productId': productId, 'receiptData': receiptBase64},
    );
    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('iOS verify failed: $status ${res.data}');
    }
  }

  Future<void> verifyAndroidPurchase({
    required String productId,
    required String purchaseToken,
    required String packageName,
  }) async {
    // New Dio-based implementation using shared CookieJar (sid) + headers
    final api = await _pizApiService;
    final res = await api.client.post<dynamic>(
      '/billing/iap/android/verify',
      data: {'productId': productId, 'purchaseToken': purchaseToken, 'packageName': packageName},
    );
    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('Android verify failed: $status ${res.data}');
    }
  }

  Future<void> notifyVerifiedPurchase({
    required String productId,
    required String platform, // 'android' | 'ios'
  }) async {
    // New Dio-based implementation using shared CookieJar (sid) + headers
    final api = await _pizApiService;
    final res = await api.client.post<dynamic>(
      '/billing/verify-success',
      data: {'productId': productId, 'platform': platform},
    );
    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('Notify verified purchase failed: $status ${res.data}');
    }
  }
}
