// mobile/lib/services/pizcloud/referral_withdrawal.service.dart

import 'package:dio/dio.dart';
import 'package:immich_mobile/models/pizcloud/referral_withdrawal.model.dart';
import 'package:immich_mobile/services/pizcloud/auth_header.service.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as pizPersist;
import 'package:immich_mobile/services/pizcloud/pizcloud_base_url.service.dart';

class ReferralWithdrawalService {
  ReferralWithdrawalService();

  final PizcloudBaseUrlService _baseUrlService = PizcloudBaseUrlService();
  final authHeaders = const AuthHeaderService();
  late final Future<pizPersist.ApiPersistCookieJarService> _pizApiService = _initPizApiService();

  Future<pizPersist.ApiPersistCookieJarService> _initPizApiService() async {
    final baseUrl = await _baseUrlService.resolveBaseUrl();
    return pizPersist.ApiPersistCookieJarService.instance(baseUrl: baseUrl);
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

    // New Dio-based implementation using PersistCookieJar (sid) + headers
    final api = await _pizApiService;
    final res = await api.client.get<dynamic>(
      '/referral/withdrawals',
      queryParameters: {
        'email': email,
        'page': page,
        'limit': limit,
        if (status != null && status.isNotEmpty) 'status': status,
      },
      options: Options(extra: const <String, dynamic>{'clientEventName': 'referral.withdrawals.list'}),
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
