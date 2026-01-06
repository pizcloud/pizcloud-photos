import 'dart:convert';

import 'package:immich_mobile/models/pizcloud/referral_payout_method.model.dart';
import 'package:immich_mobile/services/pizcloud/auth_header.service.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as pizPersist;
import 'package:immich_mobile/services/pizcloud/pizcloud_base_url.service.dart';

class ReferralPayoutMethodService {
  ReferralPayoutMethodService();

  final PizcloudBaseUrlService _baseUrlService = PizcloudBaseUrlService();
  final authHeaders = const AuthHeaderService();
  late final Future<pizPersist.ApiPersistCookieJarService> _pizApiService = _initPizApiService();

  Future<pizPersist.ApiPersistCookieJarService> _initPizApiService() async {
    final baseUrl = await _baseUrlService.resolveBaseUrl();
    return pizPersist.ApiPersistCookieJarService.instance(baseUrl: baseUrl);
  }

  /// load payout method for a given email
  Future<ReferralPayoutMethod?> loadPayoutMethod(String email) async {
    if (email.isEmpty) return null;

    // New Dio-based implementation using shared CookieJar (sid) + headers
    final api = await _pizApiService;
    final res = await api.client.get<dynamic>(
      '/referral/payout-method',
      // queryParameters: {'email': email}, // backend may infer from token; keep commented parity
    );

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      return null;
    }

    final data = res.data;
    if (data is! Map<String, dynamic>) {
      return null;
    }

    return ReferralPayoutMethod.fromJson(data);
  }

  /// save payout method
  Future<String?> savePayoutMethod({
    required String email,
    required String method, // 'bank' | 'paypal'
    String? bankName,
    String? bankAccountNumber,
    String? bankAccountHolderName,
    String? paypalEmail,
    String? paypalFullName,
  }) async {
    if (email.isEmpty) {
      return 'EMAIL_REQUIRED';
    }

    // New Dio-based implementation using shared CookieJar (sid) + headers
    final api = await _pizApiService;
    final res = await api.client.post<dynamic>(
      '/referral/payout-method',
      data: {
        'email': email,
        'method': method,
        'bankName': bankName?.trim(),
        'bankAccountNumber': bankAccountNumber?.trim(),
        'bankAccountHolderName': bankAccountHolderName?.trim(),
        'paypalEmail': paypalEmail?.trim(),
        'paypalFullName': paypalFullName?.trim(),
      },
    );

    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      return null; // success
    }

    // Parse error code from backend
    String? code;
    try {
      final data = res.data;
      if (data is Map<String, dynamic>) {
        final msg = data['message'];
        if (msg is String) {
          code = msg;
        }
      }
    } catch (_) {
      // ignore
    }

    return code ?? 'UNKNOWN_ERROR';
  }
}

final referralPayoutMethodService = ReferralPayoutMethodService();
