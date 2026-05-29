import 'package:dio/dio.dart';

import 'package:immich_mobile/config/app_config.dart';
import 'api_persist_cookie_jar.service.dart';

class AccountApi {
  AccountApi({ApiPersistCookieJarService? api}) : _api = api;

  ApiPersistCookieJarService? _api;

  Future<ApiPersistCookieJarService> _client() async {
    _api ??= await ApiPersistCookieJarService.instance(baseUrl: AppConfig.accountServiceBase);
    return _api!;
  }

  Future<Response<dynamic>> verifyIdToken(String idToken) async {
    final client = await _client();
    return client.post<dynamic>(
      '/google/verify-id-token',
      data: {'id_token': idToken},
      options: Options(extra: const <String, dynamic>{'clientEventName': 'auth.google.verify_id_token'}),
    );
  }

  Future<Response<dynamic>> verifySSoToken(String ssoToken) async {
    final client = await _client();
    return client.post<dynamic>(
      '/users/verify-sso-token',
      data: {'sso_token': ssoToken},
      options: Options(extra: const <String, dynamic>{'clientEventName': 'auth.email.verify_sso_token'}),
    );
  }

  Future<Response<dynamic>> fetchProfile() async {
    final client = await _client();
    return client.get<dynamic>('/users/me');
  }

  Future<Response<dynamic>> getPhotosApiUrl() async {
    final client = await _client();
    final serviceName = Uri.encodeQueryComponent(AppConfig.serverName);
    return client.get<dynamic>(
      '/health/service?service=$serviceName',
      options: Options(extra: const <String, dynamic>{'clientEventName': 'external.health.service_lookup'}),
    );
  }

  Future<Response<dynamic>> logout() async {
    final client = await _client();
    return client.get<dynamic>(
      '/users/logout',
      options: Options(extra: const <String, dynamic>{'clientEventName': 'auth.logout.remote'}),
    );
  }
}
