import 'dart:convert';

enum MediaType { photo, video }

enum MediaSourceType { local, remote }

class MediaThumbnails {
  final String size100;
  final String size300;
  final String size600;

  const MediaThumbnails({
    required this.size100,
    required this.size300,
    required this.size600,
  });

  factory MediaThumbnails.fromPicsumId(int id) {
    return MediaThumbnails(
      size100: 'https://picsum.photos/id/$id/100',
      size300: 'https://picsum.photos/id/$id/300',
      size600: 'https://picsum.photos/id/$id/600',
    );
  }

  factory MediaThumbnails.fromDummyId(int id) {
    return MediaThumbnails(
      size100: 'https://dummyimage.com/100x100/fff/ff0000&text=$id',
      size300: 'https://dummyimage.com/300x300/fff/ff0000&text=$id',
      size600: 'https://dummyimage.com/600x600/fff/ff0000&text=$id',
    );
  }

  factory MediaThumbnails.fromJson(Map<String, dynamic> json) {
    return MediaThumbnails(
      size100: _readString(json, 'size100'),
      size300: _readString(json, 'size300'),
      size600: _readString(json, 'size600'),
    );
  }

  factory MediaThumbnails.fallback({String? primary}) {
    final String value = _sanitizeThumbUrl(primary);
    return MediaThumbnails(size100: value, size300: value, size600: value);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'size100': size100,
      'size300': size300,
      'size600': size600,
    };
  }

  String pickForWidth(double width) {
    if (width <= 100) return size100;
    if (width <= 300) return size300;
    return size600;
  }

  String pickAdaptive({
    required double cellSize,
    required double scale,
    int? currentColCount,
    int? targetColCount,
    bool preferTargetColCount = true,
  }) {
    final int edge = adaptiveEdge(
      cellSize: cellSize,
      scale: scale,
      currentColCount: currentColCount,
      targetColCount: targetColCount,
      preferTargetColCount: preferTargetColCount,
    );
    return pickForWidth(edge.toDouble());
  }

  int adaptiveEdge({
    required double cellSize,
    required double scale,
    int? currentColCount,
    int? targetColCount,
    bool preferTargetColCount = true,
  }) {
    final double safeScale = scale <= 0 ? 1.0 : scale;
    final double visualCellSize = cellSize * safeScale;
    final int edgeFromScale = _edgeFromVisualSize(visualCellSize);
    final int edgeFromCols = _edgeFromColCount(
      currentColCount: currentColCount,
      targetColCount: targetColCount,
      preferTargetColCount: preferTargetColCount,
    );
    return edgeFromScale > edgeFromCols ? edgeFromScale : edgeFromCols;
  }

  int _edgeFromVisualSize(double size) {
    if (size <= 120) return 100;
    if (size <= 360) return 300;
    return 600;
  }

  int _edgeFromColCount({
    int? currentColCount,
    int? targetColCount,
    required bool preferTargetColCount,
  }) {
    final int cols = preferTargetColCount
        ? (targetColCount ?? currentColCount ?? 5)
        : (currentColCount ?? targetColCount ?? 5);
    if (cols <= 1) return 600;
    if (cols <= 3) return 300;
    return 100;
  }

  static String _sanitizeThumbUrl(String? value) {
    final String raw = value?.trim() ?? '';
    return raw;
  }
}

class MediaItem {
  final String id;
  final MediaType type;
  final MediaSourceType sourceType;
  final String originalUrl;
  final String? previewUrl;
  final int? width;
  final int? height;
  final MediaThumbnails thumbnails;
  final String? localPath;
  final Duration? duration;
  final DateTime? createdAt;
  final DateTime? createdLocalAt; // new
  final DateTime? addedAt;

  const MediaItem({
    required this.id,
    required this.type,
    required this.sourceType,
    required this.originalUrl,
    this.previewUrl,
    this.width,
    this.height,
    required this.thumbnails,
    this.localPath,
    this.duration,
    this.createdAt,
    this.createdLocalAt, // new
    this.addedAt,
  });

  bool get isVideo => type == MediaType.video;
  bool get isPhoto => type == MediaType.photo;
  bool get isRemote => sourceType == MediaSourceType.remote;
  bool get isLocal => sourceType == MediaSourceType.local;
  double? get aspectRatio {
    final int? w = width;
    final int? h = height;
    if (w == null || h == null || w <= 0 || h <= 0) {
      return null;
    }
    return w / h;
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final MediaType type = _mediaTypeFromString(
      _readStringOrNull(json, 'type') ?? 'photo',
    );
    final String originalUrl = _readString(
      json,
      'originalUrl',
      fallbackKey: 'original_url',
    );
    final String? previewUrl = _readStringOrNull(
      json,
      'previewUrl',
      fallbackKey: 'preview_url',
    );
    final Map<String, dynamic>? rawThumbnails = _readMapOrNull(
      json,
      'thumbnails',
    );
    final MediaThumbnails thumbnails = rawThumbnails != null
        ? MediaThumbnails.fromJson(rawThumbnails)
        : MediaThumbnails.fallback(
            primary: type == MediaType.video
                ? previewUrl
                : (previewUrl ?? originalUrl),
          );
    return MediaItem(
      id: _readString(json, 'id'),
      type: type,
      sourceType: _mediaSourceTypeFromString(
        _readStringOrNull(json, 'sourceType') ??
            _readStringOrNull(json, 'source_type') ??
            'remote',
      ),
      originalUrl: originalUrl,
      previewUrl: previewUrl,
      width: _intFromJson(json['width'] ?? json['w']),
      height: _intFromJson(json['height'] ?? json['h']),
      thumbnails: thumbnails,
      localPath: _readStringOrNull(
        json,
        'localPath',
        fallbackKey: 'local_path',
      ),
      duration: _durationFromJson(json['duration']),
      createdAt: _dateTimeFromJson(json['createdAt'] ?? json['created_at']),
      createdLocalAt: _dateTimeFromJson(
        json['createdLocalAt'] ?? json['created_local_at'],
      ), // new
      addedAt: _dateTimeFromJson(json['addedAt'] ?? json['added_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.name,
      'sourceType': sourceType.name,
      'originalUrl': originalUrl,
      'previewUrl': previewUrl,
      'width': width,
      'height': height,
      'thumbnails': thumbnails.toJson(),
      'localPath': localPath,
      'duration': duration?.inMilliseconds,
      'createdAt': createdAt?.toUtc().toIso8601String(),
      'createdLocalAt': createdLocalAt?.toIso8601String(), // new
      'addedAt': addedAt?.toUtc().toIso8601String(),
    };
  }

  static List<MediaItem> listFromJsonString(String jsonString) {
    final decoded = jsonDecode(jsonString);
    return listFromDynamic(decoded);
  }

  static List<MediaItem> listFromDynamic(dynamic source) {
    final rawList = switch (source) {
      List<dynamic> list => list,
      Map<String, dynamic> map when map['items'] is List<dynamic> =>
        map['items'] as List<dynamic>,
      _ => throw const FormatException(
        'Expected a JSON array or an object with "items" array',
      ),
    };

    return rawList
        .map((raw) {
          if (raw is! Map) {
            throw const FormatException('Each item must be a JSON object');
          }
          return MediaItem.fromJson(Map<String, dynamic>.from(raw));
        })
        .toList(growable: false);
  }

  factory MediaItem.remotePicsum({
    required int index,
    required MediaType type,
  }) {
    final thumbnails = MediaThumbnails.fromPicsumId(index);
    return MediaItem(
      id: 'remote_$index',
      type: type,
      sourceType: MediaSourceType.remote,
      originalUrl: 'https://picsum.photos/id/$index/2000',
      previewUrl: thumbnails.size300,
      width: 2000,
      height: 2000,
      thumbnails: thumbnails,
      duration: type == MediaType.video ? const Duration(seconds: 15) : null,
    );
  }

  String? pickGridThumbForEdge(int edge) {
    final List<String?> candidates = isVideo
        ? <String?>[
            thumbnails.pickForWidth(edge.toDouble()),
            previewUrl,
            thumbnails.size300,
            thumbnails.size600,
            thumbnails.size100,
          ]
        : <String?>[
            thumbnails.pickForWidth(edge.toDouble()),
            previewUrl,
            thumbnails.size300,
            thumbnails.size600,
            thumbnails.size100,
          ];
    for (final String? value in candidates) {
      final String normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

  String? pickGridThumbAdaptive({
    required double cellSize,
    required double scale,
    int? currentColCount,
    int? targetColCount,
    bool preferTargetColCount = true,
  }) {
    final int edge = thumbnails.adaptiveEdge(
      cellSize: cellSize,
      scale: scale,
      currentColCount: currentColCount,
      targetColCount: targetColCount,
      preferTargetColCount: preferTargetColCount,
    );
    return pickGridThumbForEdge(edge);
  }
}

String _readString(
  Map<String, dynamic> json,
  String key, {
  String? fallbackKey,
}) {
  final value = _readStringOrNull(json, key, fallbackKey: fallbackKey);
  if (value == null || value.isEmpty) {
    throw FormatException('Missing or invalid "$key"');
  }
  return value;
}

Map<String, dynamic>? _readMapOrNull(
  Map<String, dynamic> json,
  String key, {
  String? fallbackKey,
}) {
  final dynamic value =
      json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
  if (value == null) {
    return null;
  }
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String? _readStringOrNull(
  Map<String, dynamic> json,
  String key, {
  String? fallbackKey,
}) {
  final dynamic value =
      json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
  if (value == null) return null;
  final output = value.toString();
  return output.isEmpty ? null : output;
}

MediaType _mediaTypeFromString(String value) {
  switch (value) {
    case 'video':
      return MediaType.video;
    case 'photo':
    default:
      return MediaType.photo;
  }
}

MediaSourceType _mediaSourceTypeFromString(String value) {
  switch (value) {
    case 'local':
      return MediaSourceType.local;
    case 'remote':
    default:
      return MediaSourceType.remote;
  }
}

Duration? _durationFromJson(dynamic value) {
  if (value == null) return null;
  if (value is Duration) return value;
  if (value is int) return Duration(milliseconds: value);
  if (value is double) return Duration(milliseconds: value.round());
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return Duration(milliseconds: parsed);
  }
  throw FormatException('Invalid "duration": $value');
}

DateTime? _dateTimeFromJson(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  if (value is String) {
    final dt = DateTime.tryParse(value);
    if (dt != null) return dt;
  }
  throw FormatException('Invalid date value: $value');
}

int? _intFromJson(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) {
    return int.tryParse(value);
  }
  throw FormatException('Invalid int value: $value');
}
