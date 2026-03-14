import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:pizcloud_gallery/auth/piz_gallery_auth_context.dart'; // new

import 'viewer_dio_file_service.dart';

class ViewerCacheManager extends CacheManager with ImageCacheManager {
  static const String _cacheKey = 'viewer_image_cache_v2';
  static const double _decodeWidthOverscan = 1.2;
  static const double _maxDecodeWidthPx = 4096;

  static final ViewerCacheManager instance = ViewerCacheManager._();

  ViewerCacheManager._()
    : super(
        Config(
          _cacheKey,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 1200,
          repo: JsonCacheInfoRepository(databaseName: _cacheKey),
          fileService: ViewerDioFileService(),
        ),
      );

  static ImageProvider<Object> providerFor(
    String url, {
    int? maxWidth,
    int? maxHeight,
    int? debugIndex,
  }) {
    if (_isFilePathOrUri(url)) {
      final File? file = _fileFromPathOrUri(url);
      if (file != null) {
        return ResizeImage.resizeIfNeeded(maxWidth, maxHeight, FileImage(file));
      }
    }
    if (debugIndex != null) {
      ViewerDioFileService.registerIndexHint(url, debugIndex);
    }
    final headers = PizGalleryAuthContext.resolveHeaders(); // new
    return CachedNetworkImageProvider(
      url,
      cacheManager: instance,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      headers: headers, // new
    );
  }

  static void registerDebugIndex(String url, int index) {
    ViewerDioFileService.registerIndexHint(url, index);
  }

  static int decodeWidthForContext(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final double widthPx =
        media.size.width * media.devicePixelRatio * _decodeWidthOverscan;
    return widthPx.clamp(1, _maxDecodeWidthPx).round();
  }

  Future<bool> isCachedOnDisk(
    String url, {
    int? maxWidth,
    int? maxHeight,
  }) async {
    if (_isFilePathOrUri(url)) {
      final File? file = _fileFromPathOrUri(url);
      return file?.exists() ?? false;
    }
    if (maxWidth != null || maxHeight != null) {
      final String resizedKey = _resizedCacheKey(
        url,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
      final FileInfo? resizedInfo = await getFileFromCache(resizedKey);
      if (resizedInfo != null) {
        return true;
      }
    }

    final FileInfo? info = await getFileFromCache(url);
    return info != null;
  }

  static bool _isFilePathOrUri(String value) {
    if (value.isEmpty) return false;
    if (value.startsWith('/')) return true;
    return value.startsWith('file://');
  }

  static File? _fileFromPathOrUri(String value) {
    if (value.isEmpty) return null;
    if (value.startsWith('file://')) {
      final Uri uri = Uri.tryParse(value) ?? Uri();
      if (uri.scheme != 'file' || uri.path.isEmpty) {
        return null;
      }
      return File.fromUri(uri);
    }
    return File(value);
  }

  String _resizedCacheKey(String key, {int? maxWidth, int? maxHeight}) {
    var resizedKey = 'resized';
    if (maxWidth != null) {
      resizedKey += '_w$maxWidth';
    }
    if (maxHeight != null) {
      resizedKey += '_h$maxHeight';
    }
    resizedKey += '_$key';
    return resizedKey;
  }
}
