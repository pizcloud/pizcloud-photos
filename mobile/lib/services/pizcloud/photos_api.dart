import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:immich_mobile/config/app_config.dart';
import 'api.service.dart';

class PhotosApi {
  PhotosApi({ApiService? api}) : _api = api ?? ApiService(baseUrl: AppConfig.photosServiceBase);

  final ApiService _api;

  ApiService get api => _api;

  Future<Response<dynamic>> ssoCallback(String ssoToken) {
    return _api.get<dynamic>('/sso/callback', queryParameters: {'sso_token': ssoToken, 'continue': ''});
  }

  Future<Response<dynamic>> fetchProfile() {
    return _api.get<dynamic>('/users/me');
  }
}
