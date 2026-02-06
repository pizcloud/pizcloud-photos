class AlbumTransferUser {
  final String id;
  final String name;
  final String email;

  const AlbumTransferUser({required this.id, required this.name, required this.email});

  factory AlbumTransferUser.fromJson(Map<String, dynamic> json) => AlbumTransferUser(
    id: json['id'] as String,
    name: (json['name'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
  );
}

enum AlbumTransferStatus {
  pending,
  accepted,
  declined,
  canceled;

  static AlbumTransferStatus fromString(String value) => switch (value) {
    'pending' => AlbumTransferStatus.pending,
    'accepted' => AlbumTransferStatus.accepted,
    'declined' => AlbumTransferStatus.declined,
    'canceled' => AlbumTransferStatus.canceled,
    _ => AlbumTransferStatus.pending,
  };
}

class AlbumTransferDto {
  final String id;
  final String albumId;
  final String albumName;
  final AlbumTransferUser fromUser;
  final AlbumTransferUser toUser;
  final AlbumTransferStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? respondedAt;
  final int assetCount;
  final int totalBytes;

  const AlbumTransferDto({
    required this.id,
    required this.albumId,
    required this.albumName,
    required this.fromUser,
    required this.toUser,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.respondedAt,
    required this.assetCount,
    required this.totalBytes,
  });

  factory AlbumTransferDto.fromJson(Map<String, dynamic> json) => AlbumTransferDto(
    id: json['id'] as String,
    albumId: json['albumId'] as String,
    albumName: (json['albumName'] as String?) ?? '',
    fromUser: AlbumTransferUser.fromJson(json['fromUser'] as Map<String, dynamic>),
    toUser: AlbumTransferUser.fromJson(json['toUser'] as Map<String, dynamic>),
    status: AlbumTransferStatus.fromString((json['status'] as String?) ?? 'pending'),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    respondedAt: json['respondedAt'] != null ? DateTime.parse(json['respondedAt'] as String) : null,
    assetCount: (json['assetCount'] as num?)?.toInt() ?? 0,
    totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
  );

  bool get isPending => status == AlbumTransferStatus.pending;
}
