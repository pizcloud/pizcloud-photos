import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';

import 'account_api.service.dart';

class PhotosApiUrlResponse {
  final String url;
  final String? cluster;

  PhotosApiUrlResponse({required this.url, this.cluster});

  factory PhotosApiUrlResponse.fromJson(Map<String, dynamic> json) {
    return PhotosApiUrlResponse(url: json['url'] as String, cluster: json['cluster'] as String?);
  }
}

class PhotosBaseUrlService {
  PhotosBaseUrlService({AccountApi? accountApi}) : _accountApi = accountApi ?? AccountApi();

  final AccountApi _accountApi;

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
      final url = parsed.url.trim();

      if (url.isEmpty) {
        debugPrint('Empty url from API');
        return false;
      }

      await Store.put(StoreKey.pizcloudPhotosApiUrl, url);
      if (ref is Ref) {
        await ref.read(authProvider.notifier).validateServerUrl(url);
      } else if (ref is WidgetRef) {
        await ref.read(authProvider.notifier).validateServerUrl(url);
      }
      return true;
    } catch (e, st) {
      debugPrint('fetchAndValidateServerUrl failed: $e');
      debugPrint('$st');
      return false;
    }
  }
}
