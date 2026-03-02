import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as piz_persist;
import 'package:immich_mobile/services/pizcloud/pizcloud_base_url.service.dart';

class BackupSuccessApiService {
  BackupSuccessApiService._();

  static final PizcloudBaseUrlService _baseUrlService = PizcloudBaseUrlService();

  static Future<piz_persist.ApiPersistCookieJarService> _apiFuture() async {
    final baseUrl = await _baseUrlService.resolveBaseUrl();
    return piz_persist.ApiPersistCookieJarService.instance(baseUrl: baseUrl);
  }

  static Future<DateTime?> markBackupSuccess() async {
    final api = await _apiFuture();
    final res = await api.client.post<dynamic>('/notifications/backup-success');

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('Failed to mark backup success. status=$status');
    }

    final data = (res.data as Map<String, dynamic>? ?? const {});
    final lastSuccessfulBackupAt = data['lastSuccessfulBackupAt'];
    if (lastSuccessfulBackupAt is String && lastSuccessfulBackupAt.isNotEmpty) {
      return DateTime.tryParse(lastSuccessfulBackupAt)?.toLocal();
    }

    return null;
  }
}
