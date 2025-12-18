// mobile/lib/services/pizcloud/referral_withdrawal.service.dart

import 'package:immich_mobile/config/app_config.dart';
import 'package:immich_mobile/models/pizcloud/referral_withdrawal.model.dart';
import 'package:immich_mobile/services/pizcloud/auth_header.service.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as pizPersist;

class ReferralWithdrawalService {
  ReferralWithdrawalService() : _base = AppConfig.pizCloudServerUrl.trim().replaceAll(RegExp(r'/+$'), '');

  final String _base;
  final authHeaders = const AuthHeaderService();
  late final Future<pizPersist.ApiPersistCookieJarService> _pizApiService =
      pizPersist.ApiPersistCookieJarService.instance(baseUrl: _base, headers: authHeaders.authJson());

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

    await pizPersist.ApiPersistCookieJarService.ensureSidCookie(_base);

    // Old http-based implementation (kept for reference)
    // final uri = _buildUri(email: email, page: page, limit: limit);
    // final jsonHeaders = authHeaders.authJson();
    // final res = await http.get(uri, headers: jsonHeaders);

    // New Dio-based implementation using PersistCookieJar (sid) + headers
    final api = await _pizApiService;
    final res = await api.client.get<dynamic>(
      '/papi/referral/withdrawals',
      queryParameters: {
        'email': email,
        'page': page,
        'limit': limit,
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );

    final statusCode = res.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      return ReferralWithdrawalListResponse.empty();
    }

    final data = res.data;
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
