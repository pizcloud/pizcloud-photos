import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as piz_persist;
import 'package:immich_mobile/services/pizcloud/pizcloud_base_url.service.dart';

class BackupObservabilityApiService {
  BackupObservabilityApiService._();

  static final PizcloudBaseUrlService _baseUrlService = PizcloudBaseUrlService();

  static Future<piz_persist.ApiPersistCookieJarService> _apiFuture() async {
    final baseUrl = await _baseUrlService.resolveBaseUrl();
    return piz_persist.ApiPersistCookieJarService.instance(baseUrl: baseUrl);
  }

  static Future<void> upsertDeviceState(Map<String, dynamic> payload) async {
    final api = await _apiFuture();
    final res = await api.client.put<dynamic>('/backup-observability/device-state', data: payload);
    _ensureSuccessStatus('upsert backup observability device state', res.statusCode ?? 0);
  }

  static Future<String?> startRun(Map<String, dynamic> payload) async {
    final api = await _apiFuture();
    final res = await api.client.post<dynamic>('/backup-observability/runs', data: payload);
    _ensureSuccessStatus('start backup observability run', res.statusCode ?? 0);

    final data = res.data;
    if (data is! Map<String, dynamic>) {
      return null;
    }

    final runId = data['runId'] ?? data['id'];
    return runId is String && runId.isNotEmpty ? runId : null;
  }

  static Future<void> finishRun(String runId, Map<String, dynamic> payload) async {
    final api = await _apiFuture();
    final encodedRunId = Uri.encodeComponent(runId);
    final res = await api.client.patch<dynamic>('/backup-observability/runs/$encodedRunId', data: payload);
    _ensureSuccessStatus('finish backup observability run', res.statusCode ?? 0);
  }

  static Future<void> reportEvent(Map<String, dynamic> payload) async {
    final api = await _apiFuture();
    final res = await api.client.post<dynamic>('/backup-observability/events', data: payload);
    _ensureSuccessStatus('report backup observability event', res.statusCode ?? 0);
  }

  static Future<void> heartbeat(Map<String, dynamic> payload) async {
    final api = await _apiFuture();
    final res = await api.client.post<dynamic>('/backup-observability/heartbeat', data: payload);
    _ensureSuccessStatus('send backup observability heartbeat', res.statusCode ?? 0);
  }

  static void _ensureSuccessStatus(String action, int statusCode) {
    if (statusCode < 200 || statusCode >= 300) {
      throw Exception('Failed to $action. status=$statusCode');
    }
  }
}
