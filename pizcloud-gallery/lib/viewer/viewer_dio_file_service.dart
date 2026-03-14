import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:pizcloud_gallery/auth/piz_gallery_auth_context.dart'; // new

class ViewerDioFileService extends FileService {
  ViewerDioFileService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const int _maxHintEntries = 5000;
  static final Map<String, int> _urlIndexHints = <String, int>{};

  static void registerIndexHint(String url, int index) {
    _urlIndexHints[url] = index;
    if (_urlIndexHints.length <= _maxHintEntries) return;
    final String firstKey = _urlIndexHints.keys.first;
    _urlIndexHints.remove(firstKey);
  }

  static int? indexHintOf(String url) => _urlIndexHints[url];

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final mergedHeaders = PizGalleryAuthContext.mergeHeaders(headers); // new
    final Response<List<int>> response = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        // new
        // headers: headers,
        headers: mergedHeaders, // new
        followRedirects: true,
        maxRedirects: 5,
      ),
    );

    final List<int>? bytes = response.data;
    final int statusCode =
        response.statusCode ?? HttpStatus.internalServerError;
    final Map<String, List<String>> responseHeaders = response.headers.map;
    final Stream<List<int>> content = _trackCompletion(
      url: url,
      statusCode: statusCode,
      source: Stream<List<int>>.value(bytes ?? const <int>[]),
    );

    return _ViewerDioFileServiceResponse(
      content: content,
      statusCode: statusCode,
      headers: responseHeaders,
    );
  }

  Stream<List<int>> _trackCompletion({
    required String url,
    required int statusCode,
    required Stream<List<int>> source,
  }) {
    return source.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (List<int> data, EventSink<List<int>> sink) {
          sink.add(data);
        },
        handleDone: (EventSink<List<int>> sink) {
          final int? index = ViewerDioFileService.indexHintOf(url);
          debugPrint(
            '[ViewerDio] done index=${index ?? -1} id=${_imageId(url)} status=$statusCode $url',
          );
          sink.close();
        },
      ),
    );
  }

  String _imageId(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return 'unknown';
    final List<String> segments = uri.pathSegments;
    for (int i = 0; i < segments.length - 1; i++) {
      if (segments[i] == 'id') {
        final String id = segments[i + 1];
        if (id.isNotEmpty) return id;
      }
    }
    return 'unknown';
  }
}

class _ViewerDioFileServiceResponse implements FileServiceResponse {
  _ViewerDioFileServiceResponse({
    required Stream<List<int>> content,
    required int statusCode,
    required Map<String, List<String>> headers,
  }) : _content = content,
       _statusCode = statusCode,
       _headers = headers,
       _receivedTime = DateTime.now();

  final Stream<List<int>> _content;
  final int _statusCode;
  final Map<String, List<String>> _headers;
  final DateTime _receivedTime;

  @override
  Stream<List<int>> get content => _content;

  @override
  int? get contentLength {
    final String? header = _header(HttpHeaders.contentLengthHeader);
    return int.tryParse(header ?? '');
  }

  @override
  int get statusCode => _statusCode;

  @override
  DateTime get validTill {
    var ageDuration = const Duration(days: 7);
    final String? cacheControl = _header(HttpHeaders.cacheControlHeader);
    if (cacheControl != null) {
      final List<String> settings = cacheControl.split(',');
      for (final String setting in settings) {
        final String sanitized = setting.trim().toLowerCase();
        if (sanitized == 'no-cache') {
          ageDuration = Duration.zero;
          continue;
        }
        if (sanitized.startsWith('max-age=')) {
          final int? seconds = int.tryParse(sanitized.split('=').last);
          if (seconds != null && seconds > 0) {
            ageDuration = Duration(seconds: seconds);
          }
        }
      }
    }
    return _receivedTime.add(ageDuration);
  }

  @override
  String? get eTag => _header(HttpHeaders.etagHeader);

  @override
  String get fileExtension {
    final String? contentType = _header(HttpHeaders.contentTypeHeader);
    if (contentType == null || contentType.isEmpty) return '';
    final String lower = contentType.toLowerCase();
    if (lower.contains('image/jpeg') || lower.contains('image/jpg')) {
      return '.jpg';
    }
    if (lower.contains('image/png')) return '.png';
    if (lower.contains('image/webp')) return '.webp';
    if (lower.contains('image/gif')) return '.gif';
    if (lower.contains('image/heic')) return '.heic';
    if (lower.contains('image/heif')) return '.heif';
    if (lower.contains('image/avif')) return '.avif';
    if (lower.contains('video/mp4')) return '.mp4';
    return '';
  }

  String? _header(String name) {
    final List<String>? values = _headers[name.toLowerCase()];
    if (values == null || values.isEmpty) return null;
    return values.first;
  }
}
