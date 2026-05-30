import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:immich_mobile/domain/models/album/pizcloud/album_transfer.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as piz_persist;
import 'package:immich_mobile/services/pizcloud/pizcloud_base_url.service.dart';
import 'package:openapi/api.dart';

class AlbumTransferApiService {
  AlbumTransferApiService._();

  static final PizcloudBaseUrlService _baseUrlService = PizcloudBaseUrlService();

  static Future<piz_persist.ApiPersistCookieJarService> _apiFuture() async {
    final baseUrl = await _baseUrlService.resolveBaseUrl();
    return piz_persist.ApiPersistCookieJarService.instance(baseUrl: baseUrl);
  }

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

    // if (response.body == null || response.body.trim().isEmpty || response.body.trim() == 'null') {
    if (response.body.trim().isEmpty || response.body.trim() == 'null') {
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

  static Future<void> sendAlbumTransferOwnershipPushByEmail({
    required String albumId,
    required String toEmail,
    String? transferId,
    String? albumName,
  }) async {
    final normalizedAlbumId = albumId.trim();
    final normalizedToEmail = toEmail.trim().toLowerCase();
    final normalizedTransferId = transferId?.trim();
    final normalizedAlbumName = albumName?.trim();

    if (normalizedAlbumId.isEmpty || normalizedToEmail.isEmpty) {
      return;
    }

    final api = await _apiFuture();
    final res = await api.client.post<dynamic>(
      '/notifications/album-transfer-ownership',
      data: {
        'albumId': normalizedAlbumId,
        'toEmail': normalizedToEmail,
        if (normalizedTransferId != null && normalizedTransferId.isNotEmpty) 'transferId': normalizedTransferId,
        if (normalizedAlbumName != null && normalizedAlbumName.isNotEmpty) 'albumName': normalizedAlbumName,
      },
      options: Options(
        extra: const <String, dynamic>{'clientEventName': 'notifications.album_transfer_ownership.send'},
      ),
    );

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('Failed to send album transfer ownership push by email. status=$status');
    }
  }

  static Future<void> sendAlbumTransferOwnershipPushByEmailBestEffort({
    required String albumId,
    required String toEmail,
    String? transferId,
    String? albumName,
  }) async {
    try {
      await sendAlbumTransferOwnershipPushByEmail(
        albumId: albumId,
        toEmail: toEmail,
        transferId: transferId,
        albumName: albumName,
      );
    } catch (error, stackTrace) {
      debugPrint('sendAlbumTransferOwnershipPushByEmailBestEffort failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
