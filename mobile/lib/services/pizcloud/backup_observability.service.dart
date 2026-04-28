import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/services/pizcloud/backup_observability_api.service.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';

class BackupObservabilityCounts {
  const BackupObservabilityCounts({required this.total, required this.remainder, required this.processing});

  final int total;
  final int remainder;
  final int processing;

  Map<String, dynamic> toJson() => {'total': total, 'remainder': remainder, 'processing': processing};
}

class BackupObservabilityService {
  BackupObservabilityService._();

  static const Duration _timeout = Duration(seconds: 2);
  static const Duration _deviceStateDedupeWindow = Duration(seconds: 45);
  static const AppSettingsService _appSettingsService = AppSettingsService();
  static final Logger _logger = Logger('BackupObservabilityService');

  static String? _currentRunId;
  static DateTime? _currentRunStartedAt;
  static bool _isStartingRun = false;
  static String? _lastDeviceStateFingerprint;
  static DateTime? _lastDeviceStateSentAt;
  static String? _cachedAppVersion;

  static Future<void> upsertDeviceState({
    required String reason,
    int? selectedAlbumCount,
    int? excludedAlbumCount,
    BackupObservabilityCounts? latestKnownCounts,
    bool? backupEnabled,
    bool force = false,
  }) async {
    final identity = await _resolveTelemetryIdentity();
    if (identity == null) {
      return;
    }

    final payload = <String, dynamic>{
      'email': identity.email,
      'deviceId': identity.deviceId,
      'platform': identity.platform,
      if (identity.appVersion != null) 'appVersion': identity.appVersion,
      'backupEnabled': backupEnabled ?? _appSettingsService.getSetting(AppSettingsEnum.enableBackup),
      'networkPolicy': _buildNetworkPolicy(),
      'reason': reason,
      if (selectedAlbumCount != null) 'selectedAlbumCount': selectedAlbumCount,
      if (excludedAlbumCount != null) 'excludedAlbumCount': excludedAlbumCount,
      if (latestKnownCounts != null) 'latestKnownCounts': latestKnownCounts.toJson(),
    };

    if (!force && _isDuplicateDeviceState(payload)) {
      return;
    }

    await _runSafely<void>(
      operation: 'upsert device state',
      task: () => BackupObservabilityApiService.upsertDeviceState(payload),
    );
  }

  static Future<void> startRun({required String trigger, BackupObservabilityCounts? preRunCounts}) async {
    if (_currentRunId != null || _isStartingRun) {
      return;
    }

    final identity = await _resolveTelemetryIdentity();
    if (identity == null) {
      return;
    }

    _isStartingRun = true;
    final startedAt = DateTime.now().toUtc();

    try {
      final payload = <String, dynamic>{
        'email': identity.email,
        'deviceId': identity.deviceId,
        'platform': identity.platform,
        if (identity.appVersion != null) 'appVersion': identity.appVersion,
        'trigger': trigger,
        'startedAt': startedAt.toIso8601String(),
        if (preRunCounts != null) 'preRunCounts': preRunCounts.toJson(),
      };

      final runId = await _runSafely<String?>(
        operation: 'start run',
        task: () => BackupObservabilityApiService.startRun(payload),
      );

      if (runId != null && runId.isNotEmpty) {
        _currentRunId = runId;
        _currentRunStartedAt = startedAt;
      }
    } finally {
      _isStartingRun = false;
    }
  }

  static Future<void> finishRun({
    required String status,
    BackupObservabilityCounts? postRunCounts,
    String? failCode,
    String? failMessage,
  }) async {
    final runId = await _waitForCurrentRunId();
    if (runId == null || runId.isEmpty) {
      return;
    }

    final identity = await _resolveTelemetryIdentity();
    if (identity == null) {
      _clearCurrentRun();
      return;
    }

    final endedAt = DateTime.now().toUtc();
    final startedAt = _currentRunStartedAt;
    final payload = <String, dynamic>{
      'email': identity.email,
      'status': status,
      'endedAt': endedAt.toIso8601String(),
      if (startedAt != null) 'durationMs': endedAt.difference(startedAt).inMilliseconds,
      if (postRunCounts != null) 'postRunCounts': postRunCounts.toJson(),
      if (failCode != null && failCode.isNotEmpty) 'failCode': failCode,
      if (failMessage != null && failMessage.isNotEmpty) 'failMessage': failMessage,
    };

    await _runSafely<void>(
      operation: 'finish run',
      task: () => BackupObservabilityApiService.finishRun(runId, payload),
    );

    _clearCurrentRun();
  }

  static Future<void> reportEvent({
    required String code,
    required String stage,
    String? message,
    Object? detail,
    int? httpStatus,
    String? runId,
  }) async {
    final identity = await _resolveTelemetryIdentity();
    if (identity == null) {
      return;
    }

    final payload = <String, dynamic>{
      'email': identity.email,
      'deviceId': identity.deviceId,
      'platform': identity.platform,
      if (identity.appVersion != null) 'appVersion': identity.appVersion,
      'code': code,
      'stage': stage,
      if (message != null && message.isNotEmpty) 'message': message,
      if (detail is Map<String, dynamic> && detail.isNotEmpty) 'detail': detail,
      if (detail is String && detail.isNotEmpty) 'detail': detail,
      if (detail != null && detail is! Map<String, dynamic> && detail is! String) 'detail': detail.toString(),
      if (httpStatus != null) 'httpStatus': httpStatus,
      if (runId != null && runId.isNotEmpty)
        'runId': runId
      else if (_currentRunId != null && _currentRunId!.isNotEmpty)
        'runId': _currentRunId,
    };

    await _runSafely<void>(operation: 'report event', task: () => BackupObservabilityApiService.reportEvent(payload));
  }

  static Future<void> heartbeat({String reason = 'heartbeat'}) async {
    final identity = await _resolveTelemetryIdentity();
    if (identity == null) {
      return;
    }

    final payload = <String, dynamic>{
      'email': identity.email,
      'deviceId': identity.deviceId,
      'platform': identity.platform,
      if (identity.appVersion != null) 'appVersion': identity.appVersion,
      'reason': reason,
    };

    await _runSafely<void>(operation: 'heartbeat', task: () => BackupObservabilityApiService.heartbeat(payload));
  }

  static Future<void> reportQuotaExceeded({Object? detail}) async {
    await reportEvent(
      code: 'QUOTA_EXCEEDED',
      stage: 'UPLOAD',
      message: 'Upload blocked by quota exceeded response',
      detail: detail,
      httpStatus: 409,
    );
    await finishRun(
      status: 'failed',
      failCode: 'QUOTA_EXCEEDED',
      failMessage: 'Upload blocked by quota exceeded response',
    );
  }

  static Future<void> reportSyncRemoteFailed({required String trigger}) async {
    await reportEvent(
      code: 'SYNC_REMOTE_FAILED',
      stage: 'SYNC_REMOTE',
      message: 'Remote sync did not complete successfully before backup',
      detail: {'trigger': trigger},
    );
    await finishRun(
      status: 'failed',
      failCode: 'SYNC_REMOTE_FAILED',
      failMessage: 'Remote sync did not complete successfully before backup',
    );
  }

  static Future<void> reportBackupSuccess({BackupObservabilityCounts? postRunCounts}) async {
    await finishRun(status: 'success', postRunCounts: postRunCounts);
    await upsertDeviceState(reason: 'backup_success', latestKnownCounts: postRunCounts, force: true);
  }

  static Future<void> reportAppResume({
    int? selectedAlbumCount,
    int? excludedAlbumCount,
    BackupObservabilityCounts? latestKnownCounts,
    bool? backupEnabled,
  }) async {
    await upsertDeviceState(
      reason: 'app_resume',
      selectedAlbumCount: selectedAlbumCount,
      excludedAlbumCount: excludedAlbumCount,
      latestKnownCounts: latestKnownCounts,
      backupEnabled: backupEnabled,
    );
  }

  static Map<String, dynamic> _buildNetworkPolicy() => {
    'useCellularForUploadPhotos': _appSettingsService.getSetting(AppSettingsEnum.useCellularForUploadPhotos),
    'useCellularForUploadVideos': _appSettingsService.getSetting(AppSettingsEnum.useCellularForUploadVideos),
    'requireCharging': _appSettingsService.getSetting(AppSettingsEnum.backupRequireCharging),
    'triggerDelaySec': _appSettingsService.getSetting(AppSettingsEnum.backupTriggerDelay),
  };

  static bool _isDuplicateDeviceState(Map<String, dynamic> payload) {
    final now = DateTime.now();
    final fingerprint = jsonEncode(payload);
    final lastSentAt = _lastDeviceStateSentAt;

    if (_lastDeviceStateFingerprint == fingerprint &&
        lastSentAt != null &&
        now.difference(lastSentAt) <= _deviceStateDedupeWindow) {
      return true;
    }

    _lastDeviceStateFingerprint = fingerprint;
    _lastDeviceStateSentAt = now;
    return false;
  }

  static Future<_TelemetryIdentity?> _resolveTelemetryIdentity() async {
    final rawDeviceId = Store.tryGet<String>(StoreKey.deviceId);
    final deviceId = rawDeviceId?.trim();
    if (deviceId == null || deviceId.isEmpty) {
      return null;
    }

    final email = _resolveCurrentUserEmail();
    if (email == null) {
      return null;
    }

    return _TelemetryIdentity(
      email: email,
      deviceId: deviceId,
      platform: _platformName(),
      appVersion: await _resolveAppVersion(),
    );
  }

  static String? _resolveCurrentUserEmail() {
    final currentUser = Store.tryGet<UserDto>(StoreKey.currentUser);
    final email = currentUser?.email.trim().toLowerCase();
    if (email == null || email.isEmpty) {
      return null;
    }
    return email;
  }

  static String _platformName() {
    if (Platform.isAndroid) {
      return 'android';
    }
    if (Platform.isIOS) {
      return 'ios';
    }
    return Platform.operatingSystem.toLowerCase();
  }

  static Future<String?> _resolveAppVersion() async {
    if (_cachedAppVersion != null && _cachedAppVersion!.isNotEmpty) {
      return _cachedAppVersion;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version.trim();
      if (version.isNotEmpty) {
        _cachedAppVersion = version;
      }
    } catch (_) {
      // Ignore app version errors; telemetry must stay best-effort.
    }

    return _cachedAppVersion;
  }

  static Future<String?> _waitForCurrentRunId() async {
    if (_currentRunId != null && _currentRunId!.isNotEmpty) {
      return _currentRunId;
    }

    if (!_isStartingRun) {
      return null;
    }

    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (_currentRunId != null && _currentRunId!.isNotEmpty) {
        return _currentRunId;
      }
      if (!_isStartingRun) {
        break;
      }
    }

    return _currentRunId;
  }

  static Future<T?> _runSafely<T>({required String operation, required Future<T> Function() task}) async {
    try {
      return await task().timeout(_timeout);
    } catch (error, stack) {
      _logger.fine('Backup observability $operation failed', error, stack);
      return null;
    }
  }

  static void _clearCurrentRun() {
    _currentRunId = null;
    _currentRunStartedAt = null;
    _isStartingRun = false;
  }
}

class _TelemetryIdentity {
  const _TelemetryIdentity({
    required this.email,
    required this.deviceId,
    required this.platform,
    required this.appVersion,
  });

  final String email;
  final String deviceId;
  final String platform;
  final String? appVersion;
}
