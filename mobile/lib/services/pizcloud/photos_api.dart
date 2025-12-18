import 'package:dio/dio.dart';

import 'package:immich_mobile/config/app_config.dart';
import 'api_persist_cookie_jar.service.dart';

class PhotosApi {
  PhotosApi({ApiPersistCookieJarService? api}) : _api = api;

  ApiPersistCookieJarService? _api;

  Future<ApiPersistCookieJarService> _client() async {
    _api ??= await ApiPersistCookieJarService.instance(baseUrl: AppConfig.photosServiceBase);
    return _api!;
  }

  Future<String> get baseUrl async => (await _client()).baseUrl;
  Future<ApiPersistCookieJarService> client() => _client();

  Future<Response<dynamic>> ssoCallback(String ssoToken) async {
    final client = await _client();
    return client.get<dynamic>('/sso/callback', queryParameters: {'sso_token': ssoToken, 'continue': ''});
  }

  Future<Response<dynamic>> fetchProfile() async {
    final client = await _client();
    return client.get<dynamic>('/users/me');
  }
}
