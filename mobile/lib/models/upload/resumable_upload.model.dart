enum ResumableUploadSessionStatus {
  active('active'),
  completed('completed'),
  duplicate('duplicate'),
  deleted('deleted');

  const ResumableUploadSessionStatus(this.value);
  final String value;

  static ResumableUploadSessionStatus fromValue(String value) {
    return ResumableUploadSessionStatus.values.firstWhere(
      (item) => item.value == value,
      orElse: () => ResumableUploadSessionStatus.active,
    );
  }
}

class ResumableUploadSessionCreateRequest {
  final String deviceAssetId;
  final String deviceId;
  final String fileCreatedAt;
  final String fileModifiedAt;
  final String fileName;
  final String filename;
  final int fileSize;
  final int chunkSize;
  final int totalChunks;
  final bool isFavorite;
  final String duration;
  final String? visibility;
  final String? checksum;

  const ResumableUploadSessionCreateRequest({
    required this.deviceAssetId,
    required this.deviceId,
    required this.fileCreatedAt,
    required this.fileModifiedAt,
    required this.fileName,
    required this.filename,
    required this.fileSize,
    required this.chunkSize,
    required this.totalChunks,
    required this.isFavorite,
    required this.duration,
    this.visibility,
    this.checksum,
  });

  String get cacheKey => '$deviceAssetId:$fileSize:$fileModifiedAt';

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'deviceAssetId': deviceAssetId,
      'deviceId': deviceId,
      'fileCreatedAt': fileCreatedAt,
      'fileModifiedAt': fileModifiedAt,
      'isFavorite': isFavorite,
      'duration': duration,
      'filename': filename,
      if (visibility != null && visibility!.isNotEmpty) 'visibility': visibility,
      'fileName': fileName,
      'fileSize': fileSize,
      'chunkSize': chunkSize,
      'totalChunks': totalChunks,
      if (checksum != null && checksum!.isNotEmpty) 'checksum': checksum,
    };
  }
}

class ResumableUploadSessionCreateResponse {
  final ResumableUploadSessionStatus status;
  final String? id;
  final String? assetId;
  final bool? isTrashed;
  final int? chunkSize;
  final int? totalChunks;
  final List<int>? uploadedChunks;

  const ResumableUploadSessionCreateResponse({
    required this.status,
    this.id,
    this.assetId,
    this.isTrashed,
    this.chunkSize,
    this.totalChunks,
    this.uploadedChunks,
  });

  factory ResumableUploadSessionCreateResponse.fromMap(Map<String, dynamic> map) {
    return ResumableUploadSessionCreateResponse(
      status: ResumableUploadSessionStatus.fromValue((map['status'] as String?) ?? 'active'),
      id: map['id'] as String?,
      assetId: map['assetId'] as String?,
      isTrashed: map['isTrashed'] as bool?,
      chunkSize: (map['chunkSize'] as num?)?.toInt(),
      totalChunks: (map['totalChunks'] as num?)?.toInt(),
      uploadedChunks: _toIntList(map['uploadedChunks']),
    );
  }
}

class ResumableUploadSessionStatusResponse {
  final ResumableUploadSessionStatus status;
  final String id;
  final int chunkSize;
  final int totalChunks;
  final int fileSize;
  final List<int> uploadedChunks;

  const ResumableUploadSessionStatusResponse({
    required this.status,
    required this.id,
    required this.chunkSize,
    required this.totalChunks,
    required this.fileSize,
    required this.uploadedChunks,
  });

  factory ResumableUploadSessionStatusResponse.fromMap(Map<String, dynamic> map) {
    return ResumableUploadSessionStatusResponse(
      status: ResumableUploadSessionStatus.fromValue((map['status'] as String?) ?? 'active'),
      id: (map['id'] as String?) ?? '',
      chunkSize: (map['chunkSize'] as num?)?.toInt() ?? 0,
      totalChunks: (map['totalChunks'] as num?)?.toInt() ?? 0,
      fileSize: (map['fileSize'] as num?)?.toInt() ?? 0,
      uploadedChunks: _toIntList(map['uploadedChunks']) ?? const <int>[],
    );
  }
}

class ResumableUploadSessionChunkResponse {
  final String id;
  final int chunkIndex;
  final List<int> uploadedChunks;

  const ResumableUploadSessionChunkResponse({required this.id, required this.chunkIndex, required this.uploadedChunks});

  factory ResumableUploadSessionChunkResponse.fromMap(Map<String, dynamic> map) {
    return ResumableUploadSessionChunkResponse(
      id: (map['id'] as String?) ?? '',
      chunkIndex: (map['chunkIndex'] as num?)?.toInt() ?? 0,
      uploadedChunks: _toIntList(map['uploadedChunks']) ?? const <int>[],
    );
  }
}

class ResumableUploadSessionCacheEntry {
  final String sessionId;
  final String deviceAssetId;
  final int fileSize;
  final String fileModifiedAt;
  final int updatedAt;

  const ResumableUploadSessionCacheEntry({
    required this.sessionId,
    required this.deviceAssetId,
    required this.fileSize,
    required this.fileModifiedAt,
    required this.updatedAt,
  });

  ResumableUploadSessionCacheEntry copyWith({
    String? sessionId,
    String? deviceAssetId,
    int? fileSize,
    String? fileModifiedAt,
    int? updatedAt,
  }) {
    return ResumableUploadSessionCacheEntry(
      sessionId: sessionId ?? this.sessionId,
      deviceAssetId: deviceAssetId ?? this.deviceAssetId,
      fileSize: fileSize ?? this.fileSize,
      fileModifiedAt: fileModifiedAt ?? this.fileModifiedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'sessionId': sessionId,
      'deviceAssetId': deviceAssetId,
      'fileSize': fileSize,
      'fileModifiedAt': fileModifiedAt,
      'updatedAt': updatedAt,
    };
  }

  factory ResumableUploadSessionCacheEntry.fromMap(Map<String, dynamic> map) {
    return ResumableUploadSessionCacheEntry(
      sessionId: (map['sessionId'] as String?) ?? '',
      deviceAssetId: (map['deviceAssetId'] as String?) ?? '',
      fileSize: (map['fileSize'] as num?)?.toInt() ?? 0,
      fileModifiedAt: (map['fileModifiedAt'] as String?) ?? '',
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

List<int>? _toIntList(dynamic value) {
  if (value is! List) {
    return null;
  }
  return value.whereType<num>().map((item) => item.toInt()).toList();
}
