import 'package:flutter/foundation.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as pizPersist;
import 'package:immich_mobile/domain/models/album/pizcloud/shared_email.model.dart';
import 'package:immich_mobile/services/pizcloud/pizcloud_base_url.service.dart';

class PartnerShareEmailApiService {
  PartnerShareEmailApiService._();

  static final PizcloudBaseUrlService _baseUrlService = PizcloudBaseUrlService();
  static Future<pizPersist.ApiPersistCookieJarService> _apiFuture() async {
    final baseUrl = await _baseUrlService.resolveBaseUrl();
    return pizPersist.ApiPersistCookieJarService.instance(baseUrl: baseUrl);
  }

  static Future<List<SharedEmailDto>> getSharedEmails() async {
    final api = await _apiFuture();
    final res = await api.client.get<dynamic>('/partners/shared-emails');

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('Failed to load shared emails. status=$status');
    }

    final data = (res.data as Map<String, dynamic>);
    final items = (data['items'] as List<dynamic>? ?? []);
    return items.map((e) => SharedEmailDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<SharedEmailDto>> addSharedEmail({required String email}) async {
    final api = await _apiFuture();
    final res = await api.client.post<dynamic>('/partners/shared-emails', data: {'email': email});

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('Failed to share email. status=$status');
    }

    final data = (res.data as Map<String, dynamic>);
    final items = (data['items'] as List<dynamic>? ?? []);
    return items.map((e) => SharedEmailDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<SharedEmailDto>> removeSharedEmail({required String email}) async {
    final api = await _apiFuture();
    final res = await api.client.delete<dynamic>('/partners/shared-emails', data: {'email': email});

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('Failed to remove shared email. status=$status');
    }

    final data = (res.data as Map<String, dynamic>);
    final items = (data['items'] as List<dynamic>? ?? []);
    return items.map((e) => SharedEmailDto.fromJson(e as Map<String, dynamic>)).toList();
  }
}
