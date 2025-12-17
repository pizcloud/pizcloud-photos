import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:immich_mobile/config/app_config.dart';
import 'package:immich_mobile/models/pizcloud/referral_payout_method.model.dart';
import 'package:immich_mobile/services/pizcloud/auth_header.service.dart';
import 'package:immich_mobile/services/pizcloud/api.service.dart' as pizApi;

class ReferralPayoutMethodService {
  ReferralPayoutMethodService() : _base = AppConfig.pizCloudServerUrl.trim().replaceAll(RegExp(r'/+$'), '');

  final String _base;
  final authHeaders = const AuthHeaderService();
  late final pizApi.ApiService _pizApiService = pizApi.ApiService(baseUrl: _base, headers: authHeaders.authJson());

  Uri _buildPayoutUri({String? email}) {
    final uri = Uri.parse('$_base/papi/referral/payout-method');
    if (email == null || email.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: {'email': email});
  }

  /// load payout method for a given email
  Future<ReferralPayoutMethod?> loadPayoutMethod(String email) async {
    if (email.isEmpty) return null;

    await pizApi.ApiService.ensureSidCookie(_base);

    // Old http-based implementation (kept for reference)
    // final uri = _buildPayoutUri(email: email);
    // final uri = _buildPayoutUri();
    // final jsonHeaders = authHeaders.authJson();
    // final res = await http.get(uri, headers: jsonHeaders);

    // New Dio-based implementation using shared CookieJar (sid) + headers
    final res = await _pizApiService.client.get<dynamic>(
      '/papi/referral/payout-method',
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

    await pizApi.ApiService.ensureSidCookie(_base);

    // Old http-based implementation (kept for reference)
    // final uri = _buildPayoutUri();
    // final jsonHeaders = authHeaders.authJson();
    // final body = <String, dynamic>{
    //   'email': email,
    //   'method': method,
    //   'bankName': bankName?.trim(),
    //   'bankAccountNumber': bankAccountNumber?.trim(),
    //   'bankAccountHolderName': bankAccountHolderName?.trim(),
    //   'paypalEmail': paypalEmail?.trim(),
    //   'paypalFullName': paypalFullName?.trim(),
    // };
    // final res = await http.post(uri, headers: jsonHeaders, body: jsonEncode(body));
    // if (res.statusCode >= 200 && res.statusCode < 300) {
    //   return null; // success
    // }
    // String? code;
    // try {
    //   final data = jsonDecode(res.body);
    //   if (data is Map<String, dynamic>) {
    //     final msg = data['message'];
    //     if (msg is String) {
    //       code = msg;
    //     }
    //   }
    // } catch (_) {
    //   // ignore
    // }
    // return code ?? 'UNKNOWN_ERROR';

    // New Dio-based implementation using shared CookieJar (sid) + headers
    final res = await _pizApiService.client.post<dynamic>(
      '/papi/referral/payout-method',
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
