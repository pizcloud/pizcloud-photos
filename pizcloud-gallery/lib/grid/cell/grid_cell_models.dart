part of '../grid_cell.dart';

class _ThumbRequest {
  final String mediaId;
  final String thumbUrl;
  final int decodeSide;

  const _ThumbRequest({
    required this.mediaId,
    required this.thumbUrl,
    required this.decodeSide,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ThumbRequest &&
        other.mediaId == mediaId &&
        other.thumbUrl == thumbUrl &&
        other.decodeSide == decodeSide;
  }

  @override
  int get hashCode => Object.hash(mediaId, thumbUrl, decodeSide);
}

class _ShownThumb {
  final _ThumbRequest request;
  final ImageProvider<Object> provider;

  const _ShownThumb({required this.request, required this.provider});
}

enum _LocalSourceKind { assetThumb, assetFile, filePath, unsupported }

class _LocalSourceRequest {
  final _LocalSourceKind kind;
  final String source;
  final String cacheKey;
  final _ThumbRequest thumb;
  final String assetId;
  final int edge;
  final File? file;

  const _LocalSourceRequest._({
    required this.kind,
    required this.source,
    required this.cacheKey,
    required this.thumb,
    this.assetId = '',
    this.edge = 0,
    this.file,
  });

  factory _LocalSourceRequest.assetThumb({
    required String source,
    required String cacheKey,
    required _ThumbRequest thumb,
    required String assetId,
    required int edge,
  }) {
    return _LocalSourceRequest._(
      kind: _LocalSourceKind.assetThumb,
      source: source,
      cacheKey: cacheKey,
      thumb: thumb,
      assetId: assetId,
      edge: edge,
    );
  }

  factory _LocalSourceRequest.assetFile({
    required String source,
    required String cacheKey,
    required _ThumbRequest thumb,
    required String assetId,
  }) {
    return _LocalSourceRequest._(
      kind: _LocalSourceKind.assetFile,
      source: source,
      cacheKey: cacheKey,
      thumb: thumb,
      assetId: assetId,
    );
  }

  factory _LocalSourceRequest.filePath({
    required String source,
    required String cacheKey,
    required _ThumbRequest thumb,
    required File file,
  }) {
    return _LocalSourceRequest._(
      kind: _LocalSourceKind.filePath,
      source: source,
      cacheKey: cacheKey,
      thumb: thumb,
      file: file,
    );
  }

  factory _LocalSourceRequest.unsupported({
    required String source,
    required String cacheKey,
    required _ThumbRequest thumb,
  }) {
    return _LocalSourceRequest._(
      kind: _LocalSourceKind.unsupported,
      source: source,
      cacheKey: cacheKey,
      thumb: thumb,
    );
  }
}
