import 'package:openapi/api.dart';

class ServerFeatures {
  final bool trash;
  final bool map;
  final bool oauthEnabled;
  final bool passwordLogin;
  final bool ocr;
  final bool duplicateDetection; // pizcloud

  const ServerFeatures({
    required this.trash,
    required this.map,
    required this.oauthEnabled,
    required this.passwordLogin,
    this.ocr = false,
    this.duplicateDetection = false, // pizcloud
  });

  ServerFeatures copyWith({
    bool? trash,
    bool? map,
    bool? oauthEnabled,
    bool? passwordLogin,
    bool? ocr,
    bool? duplicateDetection, // pizcloud
  }) {
    return ServerFeatures(
      trash: trash ?? this.trash,
      map: map ?? this.map,
      oauthEnabled: oauthEnabled ?? this.oauthEnabled,
      passwordLogin: passwordLogin ?? this.passwordLogin,
      ocr: ocr ?? this.ocr,
      duplicateDetection: duplicateDetection ?? this.duplicateDetection, // pizcloud
    );
  }

  @override
  String toString() {
    return 'ServerFeatures(trash: $trash, map: $map, oauthEnabled: $oauthEnabled, passwordLogin: $passwordLogin, ocr: $ocr, duplicateDetection: $duplicateDetection)';
  }

  ServerFeatures.fromDto(ServerFeaturesDto dto)
    : trash = dto.trash,
      map = dto.map,
      oauthEnabled = dto.oauth,
      passwordLogin = dto.passwordLogin,
      ocr = dto.ocr,
      duplicateDetection = dto.duplicateDetection; // pizcloud

  @override
  bool operator ==(covariant ServerFeatures other) {
    if (identical(this, other)) return true;

    return other.trash == trash &&
        other.map == map &&
        other.oauthEnabled == oauthEnabled &&
        other.passwordLogin == passwordLogin &&
        other.ocr == ocr &&
        other.duplicateDetection == duplicateDetection;
  }

  @override
  int get hashCode {
    return trash.hashCode ^
        map.hashCode ^
        oauthEnabled.hashCode ^
        passwordLogin.hashCode ^
        ocr.hashCode ^
        duplicateDetection.hashCode;
  }
}
