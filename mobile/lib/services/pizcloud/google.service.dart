import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:immich_mobile/config/app_config.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/pizcloud/photos_base_url.service.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as pizApiPersist;
import 'account_api.service.dart';
import 'photos_api.service.dart';

/// Thin wrapper around Google Sign-In (v7) to centralize initialization and
/// requests.
class GoogleService {
  GoogleService({
    GoogleSignIn? googleSignIn,
    List<String>? scopes,
    AccountApi? accountApi,
    PhotosApi? photosApi,
    String? serverClientId,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _scopes = scopes ?? const <String>['email', 'profile'],
       _accountApi = accountApi ?? AccountApi(),
       _photosApi = photosApi ?? PhotosApi(),
       _serverClientId = serverClientId ?? AppConfig.serverClientId;

  final GoogleSignIn _googleSignIn;
  final List<String> _scopes;
  final AccountApi _accountApi;
  final PhotosApi _photosApi;
  final String _serverClientId;
  final PhotosBaseUrlService photoBaseUrlService = PhotosBaseUrlService();

  Stream<GoogleSignInAuthenticationEvent> get events => _googleSignIn.authenticationEvents;

  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;

  bool _googleInitialized = false;

  Future<void> init() async {
    final id = _serverClientId.trim();
    await _googleSignIn.initialize(serverClientId: id);
    _googleInitialized = true;
  }

  Future<void> _ensureInitialized() async {
    if (_googleInitialized) return;
    await init();
  }

  Future<GoogleSignInAccount?> attemptLightweightAuthentication() async {
    await _ensureInitialized();
    return _googleSignIn.attemptLightweightAuthentication();
  }

  Future<GoogleSignInAccount> signIn() async {
    await _ensureInitialized();
    final account = await _googleSignIn.authenticate(scopeHint: _scopes);
    debugPrint('account: $account');
    debugPrint('Email: ${account.email}');
    _currentUser = account;
    return account;
  }

  Future<LogInWithGoogleResult> logInWithGoogle({WidgetRef? ref}) async {
    final account = await signIn();
    final auth = account.authentication;
    final idToken = auth.idToken;
    debugPrint('Google ID Token: $idToken');
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google Sign-In did not return an ID token');
    }

    final verifyResponse = await _accountApi.verifyIdToken(idToken);

    // pizcloud: ensure API base URL is resolved and validated before any API calls.
    final apiReady = await photoBaseUrlService.fetchApiUrl(ref);
    if (!apiReady) {
      throw StateError('Failed to resolve photos API base URL');
    }

    final ssoToken = _extractSsoToken(verifyResponse.data);
    debugPrint('ssoToken: $ssoToken');
    if (ssoToken == null || ssoToken.isEmpty) {
      throw StateError('sso_token is missing in verifyIdToken response');
    }

    final photosResponse = await _photosApi.ssoCallback(ssoToken);
    debugPrint('photosResponse: $photosResponse');

    final authTokens = await _loadAuthTokensFromCookies();

    // final authSaved = await _saveAuthInfoIfNeeded(ref, authTokens.accessToken);
    final ensured = await photoBaseUrlService.ensureServerEndpoint(ref);
    if (!ensured) {
      throw StateError('Failed to ensure server endpoint');
    }

    // Ensure saveAuthInfo() binds and validates against the latest endpoint,
    // not a stale value left in StoreKey.serverEndpoint from a previous login.
    final authSaved = await _saveAuthInfoIfNeeded(ref, authTokens.accessToken);

    await Store.put(StoreKey.pizcloudLoginMethod, 'google');
    return LogInWithGoogleResult(
      account: account,
      idToken: idToken,
      verifyResponse: verifyResponse,
      ssoToken: ssoToken,
      photosResponse: photosResponse,
      sid: authTokens.sid,
      accessToken: authTokens.accessToken,
      authSaved: authSaved,
    );
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }

  Future<void> disconnect() async {
    await _googleSignIn.disconnect();
    _currentUser = null;
  }

  String? _extractSsoToken(dynamic data) {
    if (data is Map<String, dynamic>) {
      final token = data['sso_token'];
      if (token is String && token.isNotEmpty) return token;
    }
    return null;
  }

  Future<_AuthTokens> _loadAuthTokensFromCookies() async {
    final baseUrl = await _photosApi.baseUrl;
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final uri = Uri.parse(base).resolve('sso/callback');

    final cookies = await pizApiPersist.ApiPersistCookieJarService.loadCookiesFor(uri);

    final sid = cookies.firstWhere((c) => c.name == 'sid', orElse: () => throw 'No access token cookie').value;
    final accessToken = cookies
        .firstWhere((c) => c.name == 'pizcloud_access_token', orElse: () => throw 'No access token cookie')
        .value;

    // Persist sid for future sessions and rehydrate cookie jar now
    await _persistSid(base, sid);

    return _AuthTokens(sid: sid, accessToken: accessToken);
  }

  Future<bool?> _saveAuthInfoIfNeeded(WidgetRef? ref, String accessToken) async {
    if (ref == null) return null;

    final currentEndpoint = Store.tryGet(StoreKey.serverEndpoint);
    debugPrint('currentEndpoint: $currentEndpoint');
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
          return ref.read(authProvider.notifier).saveAuthInfo(accessToken: accessToken);
        }
        debugPrint('Missing server endpoint after re-fetch');
      }
      // pizcloud: do not fallback to defaultServer anymore.
      // try {
      //   debugPrint('re-validateServerUrl');
      //   // await photoBaseUrlService.fetchApiUrl(ref);
      //   await ref.read(authProvider.notifier).validateServerUrl(AppConfig.defaultServer);
      // } catch (e) {
      //   debugPrint('Failed to set server endpoint before saveAuthInfo: $e');
      // }
      debugPrint('Missing server endpoint before saveAuthInfo');
      return false;
    }
    return ref.read(authProvider.notifier).saveAuthInfo(accessToken: accessToken);
  }
}

class LogInWithGoogleResult {
  LogInWithGoogleResult({
    required this.account,
    required this.idToken,
    required this.verifyResponse,
    required this.ssoToken,
    required this.photosResponse,
    required this.sid,
    required this.accessToken,
    this.authSaved,
  });

  final GoogleSignInAccount account;
  final String idToken;
  final Response<dynamic> verifyResponse;
  final String ssoToken;
  final Response<dynamic> photosResponse;
  final String sid;
  final String accessToken;

  /// Result of calling `authProvider.saveAuthInfo`, if a ref was provided.
  final bool? authSaved;
}

class _AuthTokens {
  _AuthTokens({required this.sid, required this.accessToken});

  final String sid;
  final String accessToken;
}

Future<void> _persistSid(String baseUrl, String sid) async {
  await Store.put(StoreKey.pizcloudSid, sid);
  await pizApiPersist.ApiPersistCookieJarService.persistSid(baseUrl, sid);
}
