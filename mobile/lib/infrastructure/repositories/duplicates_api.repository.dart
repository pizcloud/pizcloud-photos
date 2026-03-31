import 'package:immich_mobile/infrastructure/repositories/api.repository.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:openapi/api.dart';

class DuplicatesApiRepository extends ApiRepository {
  final ApiService _apiService;

  const DuplicatesApiRepository(this._apiService);

  DuplicatesApi get _duplicatesApi => _apiService.duplicatesApi;
  AssetsApi get _assetsApi => _apiService.assetsApi;
  StacksApi get _stacksApi => _apiService.stacksApi;

  Future<List<DuplicateResponseDto>> getDuplicateGroups() {
    return checkNullWithService(_apiService, () => _duplicatesApi.getAssetDuplicates());
  }

  Future<void> resolveDuplicateGroup(String duplicateId) {
    ensureEndpoint(_apiService);
    return _duplicatesApi.deleteDuplicate(duplicateId);
  }

  Future<void> resolveDuplicateGroups(List<String> duplicateIds) async {
    if (duplicateIds.isEmpty) {
      return;
    }

    ensureEndpoint(_apiService);
    await _duplicatesApi.deleteDuplicates(BulkIdsDto(ids: duplicateIds));
  }

  Future<void> deleteAssets(List<String> assetIds, {required bool force}) async {
    if (assetIds.isEmpty) {
      return;
    }

    ensureEndpoint(_apiService);
    await _assetsApi.deleteAssets(AssetBulkDeleteDto(ids: assetIds, force: force));
  }

  Future<void> stackAssets(List<String> assetIds) async {
    if (assetIds.length < 2) {
      return;
    }

    ensureEndpoint(_apiService);
    await checkNull(_stacksApi.createStack(StackCreateDto(assetIds: assetIds)));
  }
}
