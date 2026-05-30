import 'package:dio/dio.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as piz_persist;
import 'package:immich_mobile/services/pizcloud/pizcloud_base_url.service.dart';

class BackupNotificationPreferenceApiService {
  BackupNotificationPreferenceApiService._();

  static final PizcloudBaseUrlService _baseUrlService = PizcloudBaseUrlService();

  static Future<piz_persist.ApiPersistCookieJarService> _apiFuture() async {
    final baseUrl = await _baseUrlService.resolveBaseUrl();
    return piz_persist.ApiPersistCookieJarService.instance(baseUrl: baseUrl);
  }

  static Future<bool> updateBackupPreference({required bool enabled}) async {
    final api = await _apiFuture();
    final res = await api.client.patch<dynamic>(
      '/notifications/backup-preference',
      data: {'enabled': enabled},
      options: Options(extra: const <String, dynamic>{'clientEventName': 'notifications.backup_preference.update'}),
    );

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('Failed to update backup notification preference. status=$status');
    }

    final data = (res.data as Map<String, dynamic>? ?? const {});
    final serverValue = data['backupNotificationEnabled'];
    if (serverValue is bool) {
      return serverValue;
    }

    return enabled;
  }
}
