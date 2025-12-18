import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ApiPersistCookieJarService {
  ApiPersistCookieJarService._({required this.baseUrl, required Dio dio}) : _dio = dio;

  final Dio _dio;
  final String baseUrl;

  static PersistCookieJar? _persistCookieJar;
  static Future<PersistCookieJar>? _initFuture;
  static final Map<String, ApiPersistCookieJarService> _instances = {};

  static String _normalizeBase(String baseUrl) => baseUrl.replaceAll(RegExp(r'/+$'), '');

  static Future<PersistCookieJar> _getCookieJar() async {
    if (_persistCookieJar != null) return _persistCookieJar!;
    _initFuture ??= _initJar();
    _persistCookieJar = await _initFuture;
    return _persistCookieJar!;
  }

  static Future<PersistCookieJar> _initJar() async {
    final dir = await getApplicationSupportDirectory();
    return PersistCookieJar(ignoreExpires: false, storage: FileStorage(p.join(dir.path, '.pizcloud_cookies')));
  }

  /// Singleton per baseUrl.
  static Future<ApiPersistCookieJarService> instance({
    required String baseUrl,
    Dio? dio,
    Map<String, dynamic>? headers,
  }) async {
    final normalizedBase = _normalizeBase(baseUrl);
    final existing = _instances[normalizedBase];
    if (existing != null) {
      if (headers != null && headers.isNotEmpty) {
        existing._dio.options.headers.addAll(headers);
      }
      return existing;
    }

    final jar = await _getCookieJar();
    final client =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: normalizedBase,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            headers: <String, dynamic>{'Content-Type': 'application/json', if (headers != null) ...headers},
          ),
        );
    client.interceptors.add(CookieManager(jar));

    final service = ApiPersistCookieJarService._(baseUrl: normalizedBase, dio: client);
    _instances[normalizedBase] = service;
    return service;
  }

  Dio get client => _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.get<T>(path, queryParameters: queryParameters, options: options, cancelToken: cancelToken);
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.post<T>(path, data: data, queryParameters: queryParameters, options: options, cancelToken: cancelToken);
  }

  /// Persist sid into the jar (and Store) so it survives app restarts.
  static Future<void> persistSid(String baseUrl, String sid) async {
    final jar = await _getCookieJar();
    await Store.put(StoreKey.pizcloudSid, sid);

    final normalized = _normalizeBase(baseUrl);
    final uri = Uri.parse('$normalized/');
    final cookie = Cookie('sid', sid)
      ..domain = uri.host
      ..path = '/';

    await jar.saveFromResponse(uri, [cookie]);
  }

  /// Rehydrate sid from Store into the jar in case it is missing.
  static Future<void> ensureSidCookie(String baseUrl) async {
    final sid = Store.tryGet(StoreKey.pizcloudSid);
    if (sid == null || sid.isEmpty) return;

    final jar = await _getCookieJar();
    final normalized = _normalizeBase(baseUrl);
    final uri = Uri.parse('$normalized/');
    final cookie = Cookie('sid', sid)
      ..domain = uri.host
      ..path = '/';

    await jar.saveFromResponse(uri, [cookie]);
  }

  /// Load cookies for a specific request URI from the persistent jar.
  static Future<List<Cookie>> loadCookiesFor(Uri uri) async {
    final jar = await _getCookieJar();
    return jar.loadForRequest(uri);
  }
}
