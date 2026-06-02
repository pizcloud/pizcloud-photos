import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as piz_persist;
import 'package:immich_mobile/services/pizcloud/pizcloud_base_url.service.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

enum AuthEventMethod {
  password('password'),
  oauth('oauth'),
  googleSso('google_sso'),
  emailSso('email_sso'),
  sessionLogout('session_logout');

  const AuthEventMethod(this.value);

  final String value;
}

class AuthEventService {
  AuthEventService._();

  static const Duration _requestTimeout = Duration(seconds: 1);
  static final Logger _logger = Logger('AuthEventService');
  static final PizcloudBaseUrlService _baseUrlService = PizcloudBaseUrlService();

  static Future<void> reportLoginSuccess({required AuthEventMethod method, String? source}) async {
    await _reportEvent(event: 'auth.login.result.success', method: method, source: source);
  }

  static Future<void> reportLoginFailure({
    required AuthEventMethod method,
    String? reasonCode,
    int? httpStatus,
    String? source,
  }) async {
    await _reportEvent(
      event: 'auth.login.result.failure',
      method: method,
      reasonCode: reasonCode,
      httpStatus: httpStatus,
      source: source,
    );
  }

  static Future<void> reportLoginFailureForError({
    required AuthEventMethod method,
    required Object error,
    String? source,
    String fallbackReasonCode = 'unknown',
  }) async {
    await reportLoginFailure(
      method: method,
      reasonCode: _reasonCodeForError(error, fallbackReasonCode: fallbackReasonCode),
      httpStatus: _httpStatusForError(error),
      source: source,
    );
  }

  static Future<void> reportLogoutSuccess({String? source}) async {
    await _reportEvent(event: 'auth.logout.result.success', method: AuthEventMethod.sessionLogout, source: source);
  }

  static Future<void> reportLogoutFailureForError({
    required Object error,
    String? source,
    String fallbackReasonCode = 'unknown',
  }) async {
    await _reportEvent(
      event: 'auth.logout.result.failure',
      method: AuthEventMethod.sessionLogout,
      reasonCode: _reasonCodeForError(error, fallbackReasonCode: fallbackReasonCode),
      httpStatus: _httpStatusForError(error),
      source: source,
    );
  }

  static Future<void> _reportEvent({
    required String event,
    required AuthEventMethod method,
    String? reasonCode,
    int? httpStatus,
    String? source,
  }) async {
    try {
      final baseUrl = await _resolveBaseUrl();
      if (baseUrl == null) {
        return;
      }

      final api = await piz_persist.ApiPersistCookieJarService.instance(baseUrl: baseUrl);
      final response = await api.client
          .post<dynamic>(
            '/auth/client-events',
            data: <String, dynamic>{
              'event': event,
              'method': method.value,
              'occurredAt': DateTime.now().toUtc().toIso8601String(),
              if (reasonCode != null && reasonCode.isNotEmpty) 'reasonCode': reasonCode,
              if (httpStatus != null) 'httpStatus': httpStatus,
              if (source != null && source.isNotEmpty) 'source': source,
            },
            options: Options(
              headers: const <String, dynamic>{'Accept': 'application/json'},
              extra: <String, dynamic>{'clientEventName': event},
            ),
          )
          .timeout(_requestTimeout);

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        throw Exception('Failed to report auth event. status=$statusCode');
      }
    } catch (error, stackTrace) {
      _logger.fine('Auth event $event failed', error, stackTrace);
    }
  }

  static Future<String?> _resolveBaseUrl() async {
    final cachedPizcloud = _normalizeBaseUrl(Store.tryGet(StoreKey.pizcloudApiUrl));
    if (cachedPizcloud != null) {
      return cachedPizcloud;
    }

    final cachedPhotosApi = _normalizeBaseUrl(Store.tryGet(StoreKey.pizcloudPhotosApiUrl));
    if (cachedPhotosApi != null) {
      return _stripApiSuffix(cachedPhotosApi);
    }

    final cachedServerUrl = _normalizeBaseUrl(Store.tryGet(StoreKey.serverUrl));
    if (cachedServerUrl != null) {
      return cachedServerUrl;
    }

    try {
      return await _baseUrlService.resolveBaseUrl();
    } catch (_) {
      return null;
    }
  }

  static String _reasonCodeForError(Object error, {required String fallbackReasonCode}) {
    if (error is ApiException && error.code == 401) {
      return 'invalid_credentials';
    }

    if (error is PlatformException && error.code.toLowerCase().contains('cancel')) {
      return 'user_cancelled';
    }

    final normalized = error.toString().toLowerCase();
    if (normalized.contains('missing sso_token')) {
      return 'missing_sso_token';
    }
    if (normalized.contains('oauth')) {
      return 'oauth_callback_error';
    }
    if (normalized.contains('access token cookie') || normalized.contains('server endpoint')) {
      return 'session_bootstrap_failed';
    }

    return fallbackReasonCode;
  }

  static int? _httpStatusForError(Object error) {
    if (error is ApiException) {
      final code = error.code;
      return code > 0 ? code : null;
    }

    if (error is DioException) {
      final code = error.response?.statusCode;
      return code != null && code > 0 ? code : null;
    }

    return null;
  }

  static String? _normalizeBaseUrl(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
    return normalized.isEmpty ? null : normalized;
  }

  static String _stripApiSuffix(String value) {
    return value.endsWith('/api') ? value.substring(0, value.length - 4) : value;
  }
}
