import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';

class ApiService {
  static final CookieJar _sharedCookieJar = CookieJar();
  static CookieJar get sharedCookieJar => _sharedCookieJar;

  ApiService({required String baseUrl, Dio? dio, Map<String, dynamic>? headers})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: <String, dynamic>{'Content-Type': 'application/json', if (headers != null) ...headers},
            ),
          ) {
    _dio.interceptors.add(CookieManager(_sharedCookieJar));
    // _dio.interceptors.add(
    //   InterceptorsWrapper(
    //     onRequest: (options, handler) {
    //       debugPrint('===== DIO REQUEST =====');
    //       debugPrint('METHOD : ${options.method}');
    //       debugPrint('URI    : ${options.uri}');
    //       debugPrint('baseUrl: ${options.baseUrl}');
    //       debugPrint('path   : ${options.path}');
    //       debugPrint('query  : ${options.queryParameters}');
    //       debugPrint('headers: ${options.headers}');
    //       debugPrint('=======================');
    //       handler.next(options);
    //     },
    //     onResponse: (response, handler) {
    //       debugPrint('===== DIO RESPONSE =====');
    //       debugPrint('STATUS : ${response.statusCode}');
    //       debugPrint('URI    : ${response.requestOptions.uri}');
    //       debugPrint('data   : ${response.data}');
    //       debugPrint('========================');
    //       handler.next(response);
    //     },
    //     onError: (e, handler) {
    //       debugPrint('===== DIO ERROR =====');
    //       debugPrint('STATUS : ${e.response?.statusCode}');
    //       debugPrint('URI    : ${e.requestOptions.uri}');
    //       debugPrint('message: ${e.message}');
    //       debugPrint('data   : ${e.response?.data}');
    //       debugPrint('=====================');
    //       handler.next(e);
    //     },
    //   ),
    // );
  }

  final Dio _dio;

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

  /// Restore sid from Store into the shared cookie jar for the provided baseUrl.
  /// Call this before issuing requests if the app has been restarted.
  static Future<void> ensureSidCookie(String baseUrl) async {
    final sid = Store.tryGet(StoreKey.pizcloudSid);
    debugPrint('Restoring Pizcloud SID cookie for $baseUrl: $sid');
    if (sid == null || sid.isEmpty) return;

    final normalized = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final uri = Uri.parse(normalized);
    final cookie = Cookie('sid', sid)
      ..domain = uri.host
      ..path = '/';

    await _sharedCookieJar.saveFromResponse(uri, [cookie]);
  }
}
