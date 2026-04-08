import 'package:flutter/foundation.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as pizPersist;
import 'package:immich_mobile/domain/models/album/pizcloud/shared_email.model.dart';
import 'package:immich_mobile/services/pizcloud/pizcloud_base_url.service.dart';

class AlbumShareEmailApiService {
  AlbumShareEmailApiService._();

  static final PizcloudBaseUrlService _baseUrlService = PizcloudBaseUrlService();
  static Future<pizPersist.ApiPersistCookieJarService> _apiFuture() async {
    final baseUrl = await _baseUrlService.resolveBaseUrl();
    return pizPersist.ApiPersistCookieJarService.instance(baseUrl: baseUrl);
  }

  static Future<List<SharedEmailDto>> getSharedEmails({required String albumId}) async {
    final api = await _apiFuture();
    final res = await api.client.get<dynamic>('/albums/shared-emails');
    debugPrint('res.statusCode: ${res.statusCode}');

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('Failed to load shared emails. status=$status');
    }

    final data = (res.data as Map<String, dynamic>);
    final items = (data['items'] as List<dynamic>? ?? []);
    return items.map((e) => SharedEmailDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<SharedEmailDto>> addSharedEmail({required String albumId, required String email}) async {
    final api = await _apiFuture();
    final res = await api.client.post<dynamic>('/albums/shared-emails', data: {'email': email});

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('Failed to share email. status=$status');
    }

    final data = (res.data as Map<String, dynamic>);
    final items = (data['items'] as List<dynamic>? ?? []);
    return items.map((e) => SharedEmailDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  // pizcloud
  static Future<void> sendAlbumInvitePushByEmails({required String albumId, required Iterable<String> emails}) async {
    final normalizedEmails = emails
        .map((email) => email.trim().toLowerCase())
        .where((email) => email.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (normalizedEmails.isEmpty) {
      return;
    }

    final api = await _apiFuture();
    final res = await api.client.post<dynamic>(
      '/notifications/album-invite',
      data: {'albumId': albumId, 'emails': normalizedEmails},
    );

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('Failed to send album invite push by emails. status=$status');
    }
  }

  static Future<void> sendAlbumInvitePushByEmailsBestEffort({
    required String albumId,
    required Iterable<String> emails,
  }) async {
    try {
      await sendAlbumInvitePushByEmails(albumId: albumId, emails: emails);
    } catch (error, stackTrace) {
      debugPrint('sendAlbumInvitePushByEmailsBestEffort failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
  // #pizcloud

  static Future<List<SharedEmailDto>> removeSharedEmail({required String albumId, required String email}) async {
    final api = await _apiFuture();
    final res = await api.client.delete<dynamic>('/albums/shared-emails', data: {'email': email});

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('Failed to remove shared email. status=$status');
    }

    final data = (res.data as Map<String, dynamic>);
    final items = (data['items'] as List<dynamic>? ?? []);
    return items.map((e) => SharedEmailDto.fromJson(e as Map<String, dynamic>)).toList();
  }
}
