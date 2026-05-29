import 'package:dio/dio.dart';

// import 'package:immich_mobile/config/app_config.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'api_persist_cookie_jar.service.dart';
import 'account_api.service.dart';

class PhotosApi {
  PhotosApi({ApiPersistCookieJarService? api, AccountApi? accountApi})
    : _api = api,
      _accountApi = accountApi ?? AccountApi();

  ApiPersistCookieJarService? _api;
  final AccountApi _accountApi;
  String? _baseUrlCache;

  Future<ApiPersistCookieJarService> _client() async {
    _api ??= await ApiPersistCookieJarService.instance(baseUrl: await _resolveBaseUrl());
    return _api!;
  }

  Future<String> _resolveBaseUrl() async {
    final cached = _baseUrlCache?.trim();
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final stored = Store.tryGet(StoreKey.pizcloudPhotosApiUrl);
    if (stored != null && stored.trim().isNotEmpty) {
      _baseUrlCache = stored.trim();
      return _baseUrlCache!;
    }

    final response = await _accountApi.getPhotosApiUrl();
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('Unexpected data type for photos API URL: ${data.runtimeType}');
    }

    final url = (data['photoApi'] as String?)?.trim() ?? '';
    if (url.isEmpty) {
      throw StateError('Empty photos API URL from account service');
    }

    await Store.put(StoreKey.pizcloudPhotosApiUrl, url);
    _baseUrlCache = url;
    return url;
  }

  Future<String> get baseUrl async => (await _client()).baseUrl;
  Future<ApiPersistCookieJarService> client() => _client();

  Future<Response<dynamic>> ssoCallback(String ssoToken) async {
    final client = await _client();
    return client.get<dynamic>(
      '/sso/callback',
      queryParameters: {'sso_token': ssoToken, 'continue': ''},
      options: Options(extra: const <String, dynamic>{'clientEventName': 'auth.sso.callback'}),
    );
  }

  Future<Response<dynamic>> fetchProfile() async {
    final client = await _client();
    return client.get<dynamic>(
      '/users/me',
      options: Options(extra: const <String, dynamic>{'clientEventName': 'auth.profile.get'}),
    );
  }
}
