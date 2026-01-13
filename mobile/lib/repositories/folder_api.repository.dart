import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/repositories/api.repository.dart';
import 'package:immich_mobile/services/api.service.dart'; // pizcloud
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

final folderApiRepositoryProvider = Provider((ref) => FolderApiRepository(ref.watch(apiServiceProvider))); // pizcloud
// final folderApiRepositoryProvider = Provider((ref) => FolderApiRepository(ref.watch(apiServiceProvider).viewApi)); // pizcloud

class FolderApiRepository extends ApiRepository {
  // pizcloud
  final ApiService _apiService;
  // old: held a snapshot of ViewsApi
  // final ViewsApi _api;
  final Logger _log = Logger("FolderApiRepository");

  FolderApiRepository(this._apiService);
  // FolderApiRepository(this._api);

  ViewsApi get _api => _apiService.viewApi;
  // #pizcloud

  Future<List<String>> getAllUniquePaths() async {
    try {
      // final list = await _api.getUniqueOriginalPaths();
      ensureEndpoint(_apiService); // pizcloud
      final list = await _api.getUniqueOriginalPaths();
      return list ?? [];
    } catch (e, stack) {
      _log.severe("Failed to fetch unique original links", e, stack);
      return [];
    }
  }

  Future<List<Asset>> getAssetsForPath(String? path) async {
    try {
      // final list = await _api.getAssetsByOriginalPath(path ?? '/');
      ensureEndpoint(_apiService); // pizcloud
      final list = await _api.getAssetsByOriginalPath(path ?? '/');
      return list != null ? list.map(Asset.remote).toList() : [];
    } catch (e, stack) {
      _log.severe("Failed to fetch Assets by original path", e, stack);
      return [];
    }
  }
}
