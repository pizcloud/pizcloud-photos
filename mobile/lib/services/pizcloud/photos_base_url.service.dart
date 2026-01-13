import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';

import 'account_api.service.dart';

class PhotosApiUrlResponse {
  final String photoApi;
  final String pizcloudApi;
  final String? cluster;

  PhotosApiUrlResponse({required this.photoApi, required this.pizcloudApi, this.cluster});

  factory PhotosApiUrlResponse.fromJson(Map<String, dynamic> json) {
    return PhotosApiUrlResponse(
      photoApi: json['photoApi'] as String,
      pizcloudApi: json['pizcloudApi'] as String,
      cluster: json['cluster'] as String?,
    );
  }
}

class PhotosBaseUrlService {
  PhotosBaseUrlService({AccountApi? accountApi}) : _accountApi = accountApi ?? AccountApi();

  final AccountApi _accountApi;

  // pizcloud
  String _ensureApiPath(String value) {
    final normalized = _normalizeBaseUrl(value);
    if (normalized.isEmpty) return normalized;
    return normalized.endsWith('/api') ? normalized : '$normalized/api';
  }
  // #pizcloud

  String _normalizeBaseUrl(String value) {
    return value.trim().replaceAll(RegExp(r'/+$'), '');
  }

  Future<bool> fetchApiUrl(WidgetRef? ref) async {
    return _fetchApiUrl(ref);
  }

  // Pizcloud: Adapter for non-widget callers that only have Ref.
  Future<bool> fetchApiUrlFromRef(Ref? ref) async {
    return _fetchApiUrl(ref);
  }

  Future<bool> _fetchApiUrl(Object? ref) async {
    try {
      final res = await _accountApi.getPhotosApiUrl();
      debugPrint('status: ${res.statusCode}, data: ${res.data}');

      final data = res.data;
      if (data is! Map<String, dynamic>) {
        debugPrint('Unexpected data type: ${data.runtimeType}');
        return false;
      }

      final parsed = PhotosApiUrlResponse.fromJson(data);
      final url = _normalizeBaseUrl(parsed.photoApi);
      final pizcloudUrl = _normalizeBaseUrl(parsed.pizcloudApi);

      if (url.isEmpty) {
        debugPrint('Empty url from API');
        return false;
      }
      // pizcloud
      final apiUrl = _ensureApiPath(url);
      if (apiUrl.isEmpty) {
        debugPrint('Empty apiUrl after normalization');
        return false;
      }
      // #pizcloud
      await Store.put(StoreKey.pizcloudPhotosApiUrl, apiUrl);
      if (pizcloudUrl.isNotEmpty) {
        await Store.put(StoreKey.pizcloudApiUrl, pizcloudUrl);
      }
      // pizcloud
      final parsedUrl = Uri.tryParse(url);
      if (parsedUrl == null || parsedUrl.host.isEmpty) {
        debugPrint('Invalid url from API (no host): $url');
        return false;
      }
      final ensured = await _ensureServerEndpoint(ref, url, apiUrl);
      if (!ensured) {
        return false;
      }
      // #pizcloud
      return true;
    } catch (e, st) {
      debugPrint('fetchAndValidateServerUrl failed: $e');
      debugPrint('$st');
      return false;
    }
  }

  // pizcloud
  Future<bool> _ensureServerEndpoint(Object? ref, String url, String apiUrl) async {
    if (apiUrl.isEmpty) {
      debugPrint('Empty apiUrl while ensuring server endpoint');
      return false;
    }

    // Prefer validateServerUrl to populate StoreKey.serverUrl and serverEndpoint.
    if (ref is Ref || ref is WidgetRef) {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (ref is Ref) {
          await ref.read(authProvider.notifier).validateServerUrl(url);
        } else if (ref is WidgetRef) {
          await ref.read(authProvider.notifier).validateServerUrl(url);
        }

        final endpoint = Store.tryGet(StoreKey.serverEndpoint);
        if (endpoint != null && endpoint.isNotEmpty) {
          return true;
        }
        // Small retry window for the store cache to update
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    } else {
      // old: no endpoint fallback without ref
      // await Store.put(StoreKey.serverEndpoint, apiUrl);
      await Store.put(StoreKey.serverEndpoint, apiUrl);
      await Store.put(StoreKey.serverUrl, url);
      return true;
    }

    // Fallback: if validateServerUrl did not set serverEndpoint, align it with apiUrl.
    final endpoint = Store.tryGet(StoreKey.serverEndpoint);
    if (endpoint == null || endpoint.isEmpty) {
      await Store.put(StoreKey.serverEndpoint, apiUrl);
    }
    return true;
  }

  // #pizcloud
}
