// lib/services/pizcloud/auth_header.service.dart

import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';

class AuthHeaderService {
  const AuthHeaderService();

  Map<String, String> build({bool json = false}) {
    final headers = Map<String, String>.from(ApiService.getRequestHeaders());

    headers['Accept'] = 'application/json';

    final token = Store.tryGet(StoreKey.accessToken);
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
      headers['x-immich-user-token'] = headers['x-immich-user-token'] ?? token;
    }

    if (json) {
      headers['Content-Type'] = 'application/json';
    }

    return headers;
  }

  Map<String, String> authOnly() => build(json: false);
  Map<String, String> authJson() => build(json: true);
}
