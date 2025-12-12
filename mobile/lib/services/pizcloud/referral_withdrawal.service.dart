// mobile/lib/services/pizcloud/referral_withdrawal.service.dart

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:immich_mobile/config/app_config.dart';
import 'package:immich_mobile/models/pizcloud/referral_withdrawal.model.dart';
import 'package:immich_mobile/services/pizcloud/auth_header.service.dart';

class ReferralWithdrawalService {
  ReferralWithdrawalService() : _base = AppConfig.pizCloudServerUrl.trim().replaceAll(RegExp(r'/+$'), '');

  final String _base;
  final authHeaders = const AuthHeaderService();

  Uri _buildUri({required String email, int? page, int? limit, String? status}) {
    final base = Uri.parse('$_base/papi/referral/withdrawals');
    final qp = <String, String>{'email': email};
    if (page != null) qp['page'] = page.toString();
    if (limit != null) qp['limit'] = limit.toString();
    if (status != null && status.isNotEmpty) {
      qp['status'] = status;
    }
    return base.replace(queryParameters: qp);
  }

  Future<ReferralWithdrawalListResponse> fetchWithdrawals({
    required String email,
    int page = 1,
    int limit = 20,
    String? status,
  }) async {
    if (email.isEmpty) {
      return ReferralWithdrawalListResponse.empty();
    }

    final uri = _buildUri(email: email, page: page, limit: limit);
    final jsonHeaders = authHeaders.authJson();
    final res = await http.get(uri, headers: jsonHeaders);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      return ReferralWithdrawalListResponse.empty();
    }

    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) {
      return ReferralWithdrawalListResponse.empty();
    }

    final itemsRaw = data['items'] as List<dynamic>? ?? <dynamic>[];
    final items = itemsRaw.whereType<Map<String, dynamic>>().map(ReferralWithdrawal.fromJson).toList();

    final pagination = data['pagination'] as Map<String, dynamic>? ?? const <String, dynamic>{};

    return ReferralWithdrawalListResponse(
      items: items,
      page: (pagination['page'] as num?)?.toInt() ?? page,
      limit: (pagination['limit'] as num?)?.toInt() ?? limit,
      total: (pagination['total'] as num?)?.toInt() ?? items.length,
    );
  }
}

final referralWithdrawalService = ReferralWithdrawalService();
