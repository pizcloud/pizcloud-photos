import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:pizcloud_gallery/auth/piz_gallery_auth_context.dart'; // new

class GridThumbnailCacheManager extends CacheManager {
  static const String _cacheKey = 'grid_thumbnail_cache_v1';
  // Quick perf toggle: false => no disk cache (memory cache only).
  static bool enableDiskCache = true;

  static final GridThumbnailCacheManager instance =
      GridThumbnailCacheManager._();

  GridThumbnailCacheManager._()
    : super(
        Config(
          _cacheKey,
          stalePeriod: const Duration(days: 14),
          maxNrOfCacheObjects: 3000,
          // repo: JsonCacheInfoRepository(databaseName: _cacheKey), // new
        ),
      );

  static ImageProvider<Object> buildImageProvider(
    String url, {
    int? decodeWidth,
    int? decodeHeight,
  }) {
    if (_isFilePathOrUri(url)) {
      final File? file = _fileFromPathOrUri(url);
      if (file != null) {
        return ResizeImage.resizeIfNeeded(
          decodeWidth,
          decodeHeight,
          FileImage(file),
        );
      }
    }
    // new
    final headers = PizGalleryAuthContext.resolveHeaders();
    final ImageProvider<Object> baseProvider = enableDiskCache
        ? CachedNetworkImageProvider(
            url,
            cacheManager: instance,
            headers: headers,
          )
        : NetworkImage(
            // Previous behavior:
            // NetworkImage(url)
            url,
            headers: headers,
          );
    // #new
    return ResizeImage.resizeIfNeeded(decodeWidth, decodeHeight, baseProvider);
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
}
