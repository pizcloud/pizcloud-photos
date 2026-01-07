import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/pizcloud/account_api.service.dart';

class PizcloudBaseUrlService {
  PizcloudBaseUrlService({AccountApi? accountApi}) : _accountApi = accountApi ?? AccountApi();

  final AccountApi _accountApi;
  String? _baseUrlCache;

  Future<String> resolveBaseUrl() async {
    final cached = _normalizeBaseUrl(_baseUrlCache);
    if (cached != null) {
      return cached;
    }

    final stored = Store.tryGet(StoreKey.pizcloudApiUrl);
    final storedNormalized = _normalizeBaseUrl(stored);
    if (storedNormalized != null) {
      _baseUrlCache = storedNormalized;
      return storedNormalized;
    }

    final response = await _accountApi.getPhotosApiUrl();
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('Unexpected data type for pizcloud API URL: ${data.runtimeType}');
    }

    final pizcloudApi = (data['pizcloudApi'] as String?)?.trim() ?? '';
    final photoApi = (data['photoApi'] as String?)?.trim() ?? '';
    final resolved = _normalizeBaseUrl(pizcloudApi) ?? _normalizeBaseUrl(photoApi);
    if (resolved == null) {
      throw StateError('Empty pizcloud API URL from account service');
    }

    await Store.put(StoreKey.pizcloudApiUrl, resolved);
    _baseUrlCache = resolved;
    return resolved;
  }

  String? _normalizeBaseUrl(String? value) {
    if (value == null) return null;
    final trimmed = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) return null;
    return trimmed;
  }
}
