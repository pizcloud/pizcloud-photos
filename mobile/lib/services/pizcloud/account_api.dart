import 'package:dio/dio.dart';

import 'package:immich_mobile/config/app_config.dart';
import 'api_persist_cookie_jar.service.dart';

class AccountApi {
  AccountApi({ApiPersistCookieJarService? api}) : _api = api;

  ApiPersistCookieJarService? _api;

  Future<ApiPersistCookieJarService> _client() async {
    _api ??= await ApiPersistCookieJarService.instance(
      baseUrl: AppConfig.accountServiceBase,
    );
    return _api!;
  }

  Future<Response<dynamic>> verifyIdToken(String idToken) async {
    final client = await _client();
    return client.post<dynamic>('/google/verify-id-token', data: {'id_token': idToken});
  }

  Future<Response<dynamic>> fetchProfile() async {
    final client = await _client();
    return client.get<dynamic>('/users/me');
  }

  Future<Response<dynamic>> logout() async {
    final client = await _client();
    return client.get<dynamic>('/users/logout');
  }
}
