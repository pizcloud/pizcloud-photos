import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:immich_mobile/config/app_config.dart';
import 'account_api.service.dart';
import 'photos_api.service.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as piz_api_persist;
import 'package:immich_mobile/services/pizcloud/auth_event.service.dart';
import 'package:immich_mobile/services/pizcloud/photos_base_url.service.dart';

class LoginWithEmailResult {
  const LoginWithEmailResult({
    required this.authUri,
    required this.callbackUri,
    required this.ssoToken,
    required this.accountResponse,
    required this.photosResponse,
    required this.authSaved,
  });

  final Uri authUri;
  final Uri callbackUri;
  final String ssoToken;
  final Response<dynamic> accountResponse;
  final Response<dynamic> photosResponse;
  final bool? authSaved;
}

class LoginWithEmailService {
  LoginWithEmailService({PhotosApi? photosApi, AccountApi? accountApi})
    : _photosApi = photosApi ?? PhotosApi(),
      _accountApi = accountApi ?? AccountApi();

  final PhotosApi _photosApi;
  final AccountApi _accountApi;
  final PhotosBaseUrlService photoBaseUrlService = PhotosBaseUrlService();

  Uri buildAuthUri(String email) {
    return Uri.https(AppConfig.accountHost, '/continue-with-email', {'email': email, 'service': AppConfig.service});
  }

  Future<LoginWithEmailResult> authenticate(String email, WidgetRef? ref) async {
    try {
      final authUri = buildAuthUri(email.trim());
      final callbackUrl = await FlutterWebAuth2.authenticate(
        url: authUri.toString(),
        callbackUrlScheme: 'pizcloud',
        options: const FlutterWebAuth2Options(),
        // options: const FlutterWebAuth2Options(intentFlags: ephemeralIntentFlags),
      );
      final callbackUri = Uri.parse(callbackUrl);
      final ssoToken = callbackUri.queryParameters['sso_token'];
      if (ssoToken == null || ssoToken.isEmpty) {
        throw StateError('Callback is missing sso_token');
      }

      final accountResponse = await _accountApi.verifySSoToken(ssoToken);

      // pizcloud: ensure API base URL is resolved and validated before any API calls.
      final apiReady = await photoBaseUrlService.fetchApiUrl(ref);
      if (!apiReady) {
        throw StateError('Failed to resolve photos API base URL');
      }
      final photosResponse = await _photosApi.ssoCallback(ssoToken);

      final accessToken = await _loadAccessTokenFromCookies();

      // final authSaved = await _saveAuthInfoIfNeeded(ref, accessToken);
      final ensured = await photoBaseUrlService.ensureServerEndpoint(ref);
      if (!ensured) {
        throw StateError('Failed to ensure server endpoint');
      }

      // Ensure saveAuthInfo() binds and validates against the latest endpoint,
      // not a stale value left in StoreKey.serverEndpoint from a previous login.
      final authSaved = await _saveAuthInfoIfNeeded(ref, accessToken);

      await Store.put(StoreKey.pizcloudLoginMethod, 'email');
      return LoginWithEmailResult(
        authUri: authUri,
        callbackUri: callbackUri,
        ssoToken: ssoToken,
        accountResponse: accountResponse,
        photosResponse: photosResponse,
        authSaved: authSaved,
      );
    } catch (error) {
      if (error is PlatformException && error.code.toLowerCase().contains('cancel')) {
        rethrow;
      }
      unawaited(
        AuthEventService.reportLoginFailureForError(
          method: AuthEventMethod.emailSso,
          error: error,
          source: 'mobile.email_sso.login',
          fallbackReasonCode: 'email_sso_failed',
        ),
      );
      rethrow;
    }
  }

  Future<String> _loadAccessTokenFromCookies() async {
    final baseUrl = await _photosApi.baseUrl;
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final uri = Uri.parse(base).resolve('sso/callback');

    final cookies = await piz_api_persist.ApiPersistCookieJarService.loadCookiesFor(uri);

    final sid = cookies.firstWhere((c) => c.name == 'sid', orElse: () => throw 'No access token cookie').value;
    final accessToken = cookies
        .firstWhere((c) => c.name == 'pizcloud_access_token', orElse: () => throw 'No access token cookie')
        .value;

    await _persistSid(base, sid);
    return accessToken;
  }

  Future<bool?> _saveAuthInfoIfNeeded(WidgetRef? ref, String accessToken) async {
    if (ref == null) return null;

    final currentEndpoint = Store.tryGet(StoreKey.serverEndpoint);
    if (currentEndpoint == null || currentEndpoint.isEmpty) {
      // Attempt to bootstrap endpoint again before failing login
      final apiReady = await photoBaseUrlService.fetchApiUrl(ref);
      if (apiReady) {
        final ensured = await photoBaseUrlService.ensureServerEndpoint(ref);
        if (!ensured) {
          debugPrint('Failed to ensure server endpoint after re-fetch');
          return false;
        }
        final refreshedEndpoint = Store.tryGet(StoreKey.serverEndpoint);
        if (refreshedEndpoint != null && refreshedEndpoint.isNotEmpty) {
          return await ref
              .read(authProvider.notifier)
              .saveAuthInfo(
                accessToken: accessToken,
                rememberAccount: true,
                authEventMethod: AuthEventMethod.emailSso,
                authEventSource: 'mobile.email_sso.login',
              );
        }
        debugPrint('Missing server endpoint after re-fetch');
      }
      // pizcloud: do not fallback to defaultServer anymore.
      // try {
      //   await ref.read(authProvider.notifier).validateServerUrl(AppConfig.defaultServer);
      // } catch (e) {
      //   debugPrint('Failed to set server endpoint before saveAuthInfo: $e');
      // }
      debugPrint('Missing server endpoint before saveAuthInfo');
      return false;
    }

    // Persist the access token so subsequent OpenAPI calls are authenticated
    return await ref
        .read(authProvider.notifier)
        .saveAuthInfo(
          accessToken: accessToken,
          rememberAccount: true,
          authEventMethod: AuthEventMethod.emailSso,
          authEventSource: 'mobile.email_sso.login',
        );
  }
}

Future<void> _persistSid(String baseUrl, String sid) async {
  await Store.put(StoreKey.pizcloudSid, sid);
  await piz_api_persist.ApiPersistCookieJarService.persistSid(baseUrl, sid);
}
