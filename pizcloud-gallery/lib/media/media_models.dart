enum MediaType { photo, video }

enum SyncState { localOnly, cloudOnly, synced, unknown }

class MediaItem {
  const MediaItem({
    this.id,
    this.localId,
    this.remoteId,
    this.checksum,
    required this.type,
    this.fileName,
    this.mimeType,
    this.width,
    this.height,
    this.durationMs,
    this.sizeBytes,
    this.createdAt,
    this.modifiedAt,
    this.cloudUrl,
    this.syncState = SyncState.unknown,
    required this.updatedAt,
  });

  final int? id;
  final String? localId;
  final String? remoteId;
  final String? checksum;
  final MediaType type;
  final String? fileName;
  final String? mimeType;
  final int? width;
  final int? height;
  final int? durationMs;
  final int? sizeBytes;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final String? cloudUrl;
  final SyncState syncState;
  final DateTime updatedAt;

  MediaItem copyWith({
    int? id,
    String? localId,
    String? remoteId,
    String? checksum,
    MediaType? type,
    String? fileName,
    String? mimeType,
    int? width,
    int? height,
    int? durationMs,
    int? sizeBytes,
    DateTime? createdAt,
    DateTime? modifiedAt,
    String? cloudUrl,
    SyncState? syncState,
    DateTime? updatedAt,
  }) {
    return MediaItem(
      id: id ?? this.id,
      localId: localId ?? this.localId,
      remoteId: remoteId ?? this.remoteId,
      checksum: checksum ?? this.checksum,
      type: type ?? this.type,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      cloudUrl: cloudUrl ?? this.cloudUrl,
      syncState: syncState ?? this.syncState,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toDbMap({
    bool includeLocalId = true,
    bool includeRemoteId = true,
  }) {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (includeLocalId) 'local_id': localId,
      if (includeRemoteId) 'remote_id': remoteId,
      'checksum': checksum,
      'type': _mediaTypeToString(type),
      'file_name': fileName,
      'mime_type': mimeType,
      'width': width,
      'height': height,
      'duration_ms': durationMs,
      'size_bytes': sizeBytes,
      'created_at': createdAt?.millisecondsSinceEpoch,
      'modified_at': modifiedAt?.millisecondsSinceEpoch,
      'cloud_url': cloudUrl,
      'sync_state': syncState.index,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  static MediaItem fromDbMap(Map<String, Object?> map) {
    return MediaItem(
      id: map['id'] as int?,
      localId: map['local_id'] as String?,
      remoteId: map['remote_id'] as String?,
      checksum: map['checksum'] as String?,
      type: _mediaTypeFromString(map['type'] as String?),
      fileName: map['file_name'] as String?,
      mimeType: map['mime_type'] as String?,
      width: map['width'] as int?,
      height: map['height'] as int?,
      durationMs: map['duration_ms'] as int?,
      sizeBytes: map['size_bytes'] as int?,
      createdAt: _fromMillis(map['created_at'] as int?),
      modifiedAt: _fromMillis(map['modified_at'] as int?),
      cloudUrl: map['cloud_url'] as String?,
      syncState: _syncStateFromIndex(map['sync_state'] as int?),
      updatedAt: _fromMillis(map['updated_at'] as int?) ?? DateTime.now(),
    );
  }
}

class RemoteMediaItem {
  const RemoteMediaItem({
    required this.remoteId,
    required this.type,
    this.checksum,
    this.fileName,
    this.mimeType,
    this.width,
    this.height,
    this.durationMs,
    this.sizeBytes,
    this.createdAt,
    this.modifiedAt,
    this.cloudUrl,
  });

  final String remoteId;
  final MediaType type;
  final String? checksum;
  final String? fileName;
  final String? mimeType;
  final int? width;
  final int? height;
  final int? durationMs;
  final int? sizeBytes;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final String? cloudUrl;

  MediaItem toMediaItem({DateTime? updatedAt}) {
    return MediaItem(
      remoteId: remoteId,
      checksum: checksum,
      type: type,
      fileName: fileName,
      mimeType: mimeType,
      width: width,
      height: height,
      durationMs: durationMs,
      sizeBytes: sizeBytes,
      createdAt: createdAt,
      modifiedAt: modifiedAt,
      cloudUrl: cloudUrl,
      syncState: SyncState.cloudOnly,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

DateTime? _fromMillis(int? value) {
  if (value == null) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(value);
}

String _mediaTypeToString(MediaType type) {
  switch (type) {
    case MediaType.photo:
      return 'photo';
    case MediaType.video:
      return 'video';
  }
}

MediaType _mediaTypeFromString(String? value) {
  switch (value) {
    case 'video':
      return MediaType.video;
    case 'photo':
    default:
      return MediaType.photo;
  }
}

SyncState _syncStateFromIndex(int? value) {
  if (value == null || value < 0 || value >= SyncState.values.length) {
    return SyncState.unknown;
  }
  return SyncState.values[value];
}
