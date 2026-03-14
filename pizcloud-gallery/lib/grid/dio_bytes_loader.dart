import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pizcloud_gallery/auth/piz_gallery_auth_context.dart'; // new

/// ============================
/// Dio loader bytes
/// ============================
class DioBytesLoader {
  DioBytesLoader() : _dio = Dio();

  final Dio _dio;

  Future<Uint8List> load(String url, CancelToken token) async {
    final headers = PizGalleryAuthContext.resolveHeaders(); // new
    final res = await _dio.get<List<int>>(
      url,
      // new Previous behavior:
      // options: Options(responseType: ResponseType.bytes),
      options: Options(responseType: ResponseType.bytes, headers: headers), // new
      cancelToken: token,
    );
    final data = res.data;
    if (data == null) throw Exception('Empty response');
    return Uint8List.fromList(data);
  }
}
