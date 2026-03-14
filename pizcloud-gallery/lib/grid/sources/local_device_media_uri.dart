class LocalDeviceMediaUri {
  static const String thumbScheme = 'pm-thumb';
  static const String originalScheme = 'pm-origin';
  static const String _imageCachePrefix = 'pm-image-cache';
  static const String _videoCachePrefix = 'pm-video-cache';

  static String buildThumbUri({required String assetId, required int edge}) {
    return Uri(
      scheme: thumbScheme,
      pathSegments: <String>[assetId],
      queryParameters: <String, String>{'s': '$edge'},
    ).toString();
  }

  static String buildOriginalUri(String assetId) {
    return Uri(
      scheme: originalScheme,
      pathSegments: <String>[assetId],
    ).toString();
  }

  static ({String assetId, int edge})? parseThumbUri(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != thumbScheme) {
      return null;
    }
    final String assetId = _assetIdFromUri(uri);
    if (assetId.isEmpty) {
      return null;
    }
    final int edge =
        int.tryParse(uri.queryParameters['s'] ?? '') ??
        int.tryParse(uri.queryParameters['size'] ?? '') ??
        300;
    return (assetId: assetId, edge: edge > 0 ? edge : 300);
  }

  static String? parseOriginalAssetId(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != originalScheme) {
      return null;
    }
    final String assetId = _assetIdFromUri(uri);
    if (assetId.isEmpty) {
      return null;
    }
    return assetId;
  }

  static String buildTypedThumbCacheKey(
    String source, {
    required bool isVideo,
  }) {
    final String normalized = source.trim();
    final String prefix = isVideo ? _videoCachePrefix : _imageCachePrefix;
    return '$prefix::$normalized';
  }

  static String _assetIdFromUri(Uri uri) {
    if (uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.join('/');
    }
    final String path = uri.path;
    if (path.isEmpty) {
      return '';
    }
    return path.startsWith('/') ? path.substring(1) : path;
  }
}
