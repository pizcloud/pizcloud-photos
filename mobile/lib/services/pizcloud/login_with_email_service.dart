import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:immich_mobile/config/app_config.dart';
import 'account_api.dart';
import 'photos_api.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as pizApiPersist;

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

  Uri buildAuthUri(String email) {
    return Uri.https(AppConfig.accountHost, '/continue-with-email', {'email': email, 'service': AppConfig.service});
  }

  Future<LoginWithEmailResult> authenticate(String email, WidgetRef? ref) async {
    final authUri = buildAuthUri(email.trim());
    final callbackUrl = await FlutterWebAuth2.authenticate(
      url: authUri.toString(),
      callbackUrlScheme: 'pizcloud',
      options: const FlutterWebAuth2Options(intentFlags: ephemeralIntentFlags),
    );
    final callbackUri = Uri.parse(callbackUrl);
    final ssoToken = callbackUri.queryParameters['sso_token'];
    if (ssoToken == null || ssoToken.isEmpty) {
      throw StateError('Callback is missing sso_token');
    }

    final accountResponse = await _accountApi.verifySSoToken(ssoToken);
    final photosResponse = await _photosApi.ssoCallback(ssoToken);
    // ===============

    final baseUrl = await _photosApi.baseUrl;
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final uri = Uri.parse(base).resolve('sso/callback');

    final cookies = await pizApiPersist.ApiPersistCookieJarService.loadCookiesFor(uri);

    final sid = cookies.firstWhere((c) => c.name == 'sid', orElse: () => throw 'No access token cookie').value;
    final accessToken = cookies
        .firstWhere((c) => c.name == 'pizcloud_access_token', orElse: () => throw 'No access token cookie')
        .value;

    await _persistSid(base, sid);

    bool? authSaved;
    if (ref != null) {
      // Ensure the Immich API endpoint is configured before saving auth info
      final currentEndpoint = Store.tryGet(StoreKey.serverEndpoint);
      if (currentEndpoint == null || currentEndpoint.isEmpty) {
        try {
          await ref.read(authProvider.notifier).validateServerUrl(AppConfig.defaultServer);
        } catch (e) {
          debugPrint('Failed to set server endpoint before saveAuthInfo: $e');
        }
      }

      // Persist the Immich access token so subsequent OpenAPI calls are authenticated
      authSaved = await ref.read(authProvider.notifier).saveAuthInfo(accessToken: accessToken);
    }

    return LoginWithEmailResult(
      authUri: authUri,
      callbackUri: callbackUri,
      ssoToken: ssoToken,
      accountResponse: accountResponse,
      photosResponse: photosResponse,
      authSaved: authSaved,
    );
  }
}

Future<void> _persistSid(String baseUrl, String sid) async {
  await Store.put(StoreKey.pizcloudSid, sid);
  await pizApiPersist.ApiPersistCookieJarService.persistSid(baseUrl, sid);
}
