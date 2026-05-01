import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';

String _normalizeApiBaseUrl(String rawUrl) {
  final trimmed = rawUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) {
    return trimmed;
  }
  return trimmed.endsWith('/api') ? trimmed : '$trimmed/api';
}

/// Returns the upload endpoint with backward-compatible fallback.
///
/// - Primary: StoreKey.uploadEndpoint (if provided by /health/service as `uploadApi`)
/// - Fallback: StoreKey.serverEndpoint (existing behavior)
String getUploadEndpoint() {
  final uploadEndpoint = Store.tryGet(StoreKey.uploadEndpoint);
  if (uploadEndpoint != null && uploadEndpoint.isNotEmpty) {
    return _normalizeApiBaseUrl(uploadEndpoint);
  }

  final serverEndpoint = Store.tryGet(StoreKey.serverEndpoint) ?? '';
  return _normalizeApiBaseUrl(serverEndpoint);
}
