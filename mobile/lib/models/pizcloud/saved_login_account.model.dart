import 'package:immich_mobile/domain/models/user.model.dart';

class SavedLoginAccount {
  const SavedLoginAccount({
    required this.userId,
    required this.email,
    required this.name,
    required this.avatarColor,
    required this.hasProfileImage,
    required this.profileChangedAt,
    required this.lastLoginAt,
  });

  final String userId;
  final String email;
  final String name;
  final AvatarColor avatarColor;
  final bool hasProfileImage;
  final DateTime profileChangedAt;
  final DateTime lastLoginAt;

  SavedLoginAccount copyWith({
    String? userId,
    String? email,
    String? name,
    AvatarColor? avatarColor,
    bool? hasProfileImage,
    DateTime? profileChangedAt,
    DateTime? lastLoginAt,
  }) {
    return SavedLoginAccount(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      name: name ?? this.name,
      avatarColor: avatarColor ?? this.avatarColor,
      hasProfileImage: hasProfileImage ?? this.hasProfileImage,
      profileChangedAt: profileChangedAt ?? this.profileChangedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  factory SavedLoginAccount.fromUser(UserDto user, DateTime lastLoginAt) {
    return SavedLoginAccount(
      userId: user.id,
      email: user.email,
      name: user.name,
      avatarColor: user.avatarColor,
      hasProfileImage: user.hasProfileImage,
      profileChangedAt: user.profileChangedAt,
      lastLoginAt: lastLoginAt,
    );
  }

  factory SavedLoginAccount.fromJson(Map<String, dynamic> json) {
    final avatarColorValue = json['avatarColor'] as String?;
    final avatarColor = AvatarColor.values.firstWhere(
      (color) => color.value == avatarColorValue,
      orElse: () => AvatarColor.primary,
    );

    final profileChangedAtValue = json['profileChangedAt'] as String?;
    final lastLoginAtValue = json['lastLoginAt'] as String?;

    return SavedLoginAccount(
      userId: json['userId'] as String? ?? '',
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarColor: avatarColor,
      hasProfileImage: json['hasProfileImage'] as bool? ?? false,
      profileChangedAt:
          profileChangedAtValue != null ? DateTime.parse(profileChangedAtValue) : DateTime.fromMillisecondsSinceEpoch(0),
      lastLoginAt: lastLoginAtValue != null ? DateTime.parse(lastLoginAtValue) : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'email': email,
      'name': name,
      'avatarColor': avatarColor.value,
      'hasProfileImage': hasProfileImage,
      'profileChangedAt': profileChangedAt.toIso8601String(),
      'lastLoginAt': lastLoginAt.toIso8601String(),
    };
  }
}
