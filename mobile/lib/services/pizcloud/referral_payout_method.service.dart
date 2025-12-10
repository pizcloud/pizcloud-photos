import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:immich_mobile/config/app_config.dart';
import 'package:immich_mobile/models/pizcloud/referral_payout_method.model.dart';

class ReferralPayoutMethodService {
  ReferralPayoutMethodService() : _base = AppConfig.pizCloudServerUrl.trim().replaceAll(RegExp(r'/+$'), '');

  final String _base;

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

    final uri = _buildPayoutUri(email: email);
    final res = await http.get(uri);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      return null;
    }

    final data = jsonDecode(res.body);
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

    final uri = _buildPayoutUri();

    final body = <String, dynamic>{
      'email': email,
      'method': method,
      'bankName': bankName?.trim(),
      'bankAccountNumber': bankAccountNumber?.trim(),
      'bankAccountHolderName': bankAccountHolderName?.trim(),
      'paypalEmail': paypalEmail?.trim(),
      'paypalFullName': paypalFullName?.trim(),
    };

    final res = await http.post(uri, headers: const {'Content-Type': 'application/json'}, body: jsonEncode(body));

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return null; // success
    }

    // Parse error code from backend
    String? code;
    try {
      final data = jsonDecode(res.body);
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
