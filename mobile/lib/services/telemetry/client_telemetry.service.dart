import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:immich_mobile/config/app_config.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

class ClientTelemetryMeta {
  const ClientTelemetryMeta({
    required this.requestId,
    required this.correlationId,
    required this.clientEventId,
    required this.clientSessionId,
  });

  final String requestId;
  final String correlationId;
  final String clientEventId;
  final String clientSessionId;

  Map<String, String> toMap() {
    return <String, String>{
      'requestId': requestId,
      'correlationId': correlationId,
      'clientEventId': clientEventId,
      'clientSessionId': clientSessionId,
    };
  }
}

class ClientTelemetryService {
  ClientTelemetryService._();

  static final ClientTelemetryService I = ClientTelemetryService._();
  static const Uuid _uuid = Uuid();
  static const int _maxStringLength = 512;

  String? _sessionId;
  String? _correlationId;
  String _appVersion = 'unknown';
  String _buildNumber = 'unknown';
  Future<void>? _buildInfoFuture;

  bool get isEnabled {
    if (!AppConfig.enableClientTelemetry) {
      return false;
    }

    final runtimeOverride = Store.tryGet<bool>(StoreKey.clientTelemetryEnabled);
    return runtimeOverride ?? true;
  }

  bool get isConsoleEnabled {
    if (!isEnabled) {
      return false;
    }

    if (AppConfig.enableClientTelemetryConsole) {
      return true;
    }

    return kDebugMode;
  }

  Future<void> setRuntimeEnabled(bool enabled) async {
    await Store.put(StoreKey.clientTelemetryEnabled, enabled);
  }

  Future<void> clearRuntimeOverride() async {
    await Store.delete(StoreKey.clientTelemetryEnabled);
  }

  Future<ClientTelemetryMeta?> attachHeadersToMap(Map<String, dynamic> headers, {String? eventName}) async {
    if (!isEnabled) {
      return null;
    }

    try {
      await _ensureBuildInfo();
      final requestId = _ensureHeader(headers, 'x-request-id', () => _createId('req'));
      final correlationId = _ensureHeader(headers, 'x-correlation-id', _getOrCreateCorrelationId);
      final eventId = _ensureHeader(headers, 'x-client-event-id', () => _createId('evt'));
      final sessionId = _ensureHeader(headers, 'x-client-session-id', _getOrCreateSessionId);

      _putHeaderIfMissing(headers, 'x-client-platform', _platform());
      _putHeaderIfMissing(headers, 'x-client-app-version', _appVersion);
      _putHeaderIfMissing(headers, 'x-client-build-number', _buildNumber);

      final normalizedEventName = (eventName ?? '').trim();
      if (normalizedEventName.isNotEmpty) {
        _putHeaderIfMissing(headers, 'x-client-event-name', normalizedEventName);
      }

      return ClientTelemetryMeta(
        requestId: requestId,
        correlationId: correlationId,
        clientEventId: eventId,
        clientSessionId: sessionId,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ClientTelemetryMeta?> attachHeadersToStringMap(Map<String, String> headers, {String? eventName}) async {
    final nextHeaders = <String, dynamic>{};
    nextHeaders.addAll(headers);
    final meta = await attachHeadersToMap(nextHeaders, eventName: eventName);
    headers
      ..clear()
      ..addAll(nextHeaders.map((key, value) => MapEntry(key, value.toString())));
    return meta;
  }

  void logHttpRequest({
    required String transport,
    required String method,
    required Uri uri,
    ClientTelemetryMeta? meta,
    String? eventName,
  }) {
    _safeLog('info', <String, dynamic>{
      'event': 'http.request',
      'transport': transport,
      'method': method.toUpperCase(),
      'path': _toSafePath(uri),
      'clientEventName': eventName ?? '',
      ...?meta?.toMap(),
    });
  }

  void logHttpResponse({
    required String transport,
    required String method,
    required Uri uri,
    required int status,
    required int durationMs,
    ClientTelemetryMeta? meta,
    String? eventName,
  }) {
    _safeLog('info', <String, dynamic>{
      'event': 'http.response',
      'transport': transport,
      'method': method.toUpperCase(),
      'path': _toSafePath(uri),
      'status': status,
      'durationMs': durationMs,
      'clientEventName': eventName ?? '',
      ...?meta?.toMap(),
    });
  }

  void logHttpError({
    required String transport,
    required String method,
    required Uri uri,
    required Object error,
    required int durationMs,
    ClientTelemetryMeta? meta,
    String? eventName,
  }) {
    _safeLog('error', <String, dynamic>{
      'event': 'http.error',
      'transport': transport,
      'method': method.toUpperCase(),
      'path': _toSafePath(uri),
      'durationMs': durationMs,
      'error': error.toString(),
      'clientEventName': eventName ?? '',
      ...?meta?.toMap(),
    });
  }

  dynamic redactForTelemetry(dynamic value, [String keyPath = '']) {
    if (value == null) {
      return null;
    }

    if (value is String) {
      if (_shouldRedactByKey(keyPath)) {
        return _maskString(value);
      }

      if (value.length > _maxStringLength) {
        return '${value.substring(0, _maxStringLength)}...[truncated]';
      }

      return value;
    }

    if (value is num || value is bool) {
      return value;
    }

    if (value is Map) {
      final output = <String, dynamic>{};
      value.forEach((dynamic key, dynamic innerValue) {
        final normalizedKey = key.toString();
        final nextPath = keyPath.isEmpty ? normalizedKey : '$keyPath.$normalizedKey';
        output[normalizedKey] = redactForTelemetry(innerValue, nextPath);
      });
      return output;
    }

    if (value is Iterable) {
      var index = 0;
      return value
          .map((dynamic item) {
            final nextPath = '$keyPath[$index]';
            index += 1;
            return redactForTelemetry(item, nextPath);
          })
          .toList(growable: false);
    }

    return value.toString();
  }

  String _createId(String prefix) => '${prefix}_${_uuid.v4()}';

  String _getOrCreateSessionId() {
    final current = _sessionId;
    if (current != null && current.isNotEmpty) {
      return current;
    }

    final next = _createId('sid');
    _sessionId = next;
    return next;
  }

  String _getOrCreateCorrelationId() {
    final current = _correlationId;
    if (current != null && current.isNotEmpty) {
      return current;
    }

    final next = _createId('cid');
    _correlationId = next;
    return next;
  }

  Future<void> _ensureBuildInfo() async {
    _buildInfoFuture ??= _loadBuildInfo();
    await _buildInfoFuture;
  }

  Future<void> _loadBuildInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version.trim();
      final buildNumber = packageInfo.buildNumber.trim();

      _appVersion = version.isNotEmpty ? version : _appVersion;
      _buildNumber = buildNumber.isNotEmpty ? buildNumber : _buildNumber;
    } catch (_) {
      // Best effort only.
    }
  }

  void _safeLog(String level, Map<String, dynamic> payload) {
    if (!isConsoleEnabled) {
      return;
    }

    try {
      final redacted = redactForTelemetry(payload);
      final line = jsonEncode(redacted);
      debugPrint('[client.telemetry][$level] $line');
    } catch (_) {
      // fail-open
    }
  }

  String _platform() {
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return 'mobile';
    }
  }

  String _toSafePath(Uri uri) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port${uri.path}';
  }

  bool _shouldRedactByKey(String keyPath) {
    final normalized = keyPath.toLowerCase();
    return normalized.contains('token') ||
        normalized.contains('password') ||
        normalized.contains('authorization') ||
        normalized.contains('cookie') ||
        normalized.contains('email') ||
        normalized.contains('purchase') ||
        normalized.contains('orderid') ||
        normalized.contains('order_id');
  }

  String _maskString(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return normalized;
    }

    if (normalized.contains('@')) {
      final parts = normalized.split('@');
      if (parts.length != 2) {
        return '***';
      }
      final head = parts[0];
      final tail = parts[1];
      if (head.isEmpty || tail.isEmpty) {
        return '***';
      }
      return '${head[0]}***@$tail';
    }

    if (normalized.length <= 8) {
      return '***';
    }

    return '${normalized.substring(0, 3)}***${normalized.substring(normalized.length - 2)}';
  }

  String _ensureHeader(Map<String, dynamic> headers, String key, String Function() fallbackFactory) {
    final existing = _getHeaderValue(headers, key);
    if (existing.isNotEmpty) {
      return existing;
    }

    final next = fallbackFactory();
    headers[key] = next;
    return next;
  }

  void _putHeaderIfMissing(Map<String, dynamic> headers, String key, String value) {
    if (_getHeaderValue(headers, key).isNotEmpty) {
      return;
    }

    headers[key] = value;
  }

  String _getHeaderValue(Map<String, dynamic> headers, String key) {
    final target = key.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != target) {
        continue;
      }

      final raw = entry.value?.toString().trim();
      if (raw != null && raw.isNotEmpty) {
        return raw;
      }
    }

    return '';
  }
}
