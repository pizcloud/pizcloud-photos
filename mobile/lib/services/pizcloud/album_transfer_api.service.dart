import 'dart:convert';

import 'package:immich_mobile/domain/models/album/pizcloud/album_transfer.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:openapi/api.dart';

class AlbumTransferApiService {
  AlbumTransferApiService._();

  static void _ensureEndpoint(ApiService apiService) {
    final endpoint = Store.tryGet(StoreKey.serverEndpoint);
    if (endpoint == null || endpoint.isEmpty) {
      return;
    }
    if (apiService.apiClient.basePath == endpoint) {
      return;
    }
    apiService.setEndpoint(endpoint);
  }

  static Future<List<AlbumTransferDto>> getIncoming(ApiService apiService) async {
    _ensureEndpoint(apiService);
    final response = await apiService.apiClient.invokeAPI(
      '/album-transfers/incoming',
      'GET',
      [],
      null,
      {},
      {},
      'application/json',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((e) => AlbumTransferDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<AlbumTransferDto?> getAlbumTransfer(ApiService apiService, String albumId) async {
    _ensureEndpoint(apiService);
    final response = await apiService.apiClient.invokeAPI(
      '/albums/$albumId/transfer',
      'GET',
      [],
      null,
      {},
      {},
      'application/json',
    );

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }

    if (response.body == null || response.body.trim().isEmpty || response.body.trim() == 'null') {
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AlbumTransferDto.fromJson(data);
  }

  static Future<AlbumTransferDto> requestTransfer(
    ApiService apiService, {
    required String albumId,
    required String toUserId,
  }) async {
    _ensureEndpoint(apiService);
    final response = await apiService.apiClient.invokeAPI(
      '/albums/$albumId/transfer',
      'POST',
      [],
      {'toUserId': toUserId},
      {},
      {},
      'application/json',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AlbumTransferDto.fromJson(data);
  }

  static Future<AlbumTransferDto> cancelTransfer(ApiService apiService, String albumId) async {
    _ensureEndpoint(apiService);
    final response = await apiService.apiClient.invokeAPI(
      '/albums/$albumId/transfer/cancel',
      'POST',
      [],
      null,
      {},
      {},
      'application/json',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AlbumTransferDto.fromJson(data);
  }

  static Future<AlbumTransferDto> acceptTransfer(ApiService apiService, String transferId) async {
    _ensureEndpoint(apiService);
    final response = await apiService.apiClient.invokeAPI(
      '/album-transfers/$transferId/accept',
      'POST',
      [],
      null,
      {},
      {},
      'application/json',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AlbumTransferDto.fromJson(data);
  }

  static Future<AlbumTransferDto> declineTransfer(ApiService apiService, String transferId) async {
    _ensureEndpoint(apiService);
    final response = await apiService.apiClient.invokeAPI(
      '/album-transfers/$transferId/decline',
      'POST',
      [],
      null,
      {},
      {},
      'application/json',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AlbumTransferDto.fromJson(data);
  }
}
