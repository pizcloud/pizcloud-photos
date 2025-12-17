import 'package:dio/dio.dart';

import 'package:immich_mobile/config/app_config.dart';
import 'api.service.dart';

class AccountApi {
  AccountApi({ApiService? api}) : _api = api ?? ApiService(baseUrl: AppConfig.accountServiceBase);

  final ApiService _api;

  ApiService get api => _api;

  Future<Response<dynamic>> verifyIdToken(String idToken) {
    return _api.post<dynamic>('/google/verify-id-token', data: {'id_token': idToken});
  }

  Future<Response<dynamic>> fetchProfile() {
    return _api.get<dynamic>('/users/me');
  }

  Future<Response<dynamic>> logout() {
    return _api.get<dynamic>('/users/logout');
  }
}
