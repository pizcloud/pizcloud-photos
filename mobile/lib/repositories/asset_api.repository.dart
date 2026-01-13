import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/stack.model.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/repositories/api.repository.dart';
import 'package:immich_mobile/services/api.service.dart'; // pizcloud
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:openapi/api.dart';

final assetApiRepositoryProvider = Provider(
  // pizcloud
  (ref) => AssetApiRepository(ref.watch(apiServiceProvider)),
);
// old: bound API instances once at provider creation time
// final assetApiRepositoryProvider = Provider(
//   (ref) => AssetApiRepository(
//     ref.watch(apiServiceProvider).assetsApi,
//     ref.watch(apiServiceProvider).searchApi,
//     ref.watch(apiServiceProvider).stacksApi,
//     ref.watch(apiServiceProvider).trashApi,
//   ),
// );
// #pizcloud

class AssetApiRepository extends ApiRepository {
  // pizcloud
  final ApiService _apiService;
  // old: held snapshots of API instances
  // final AssetsApi _api;
  // final SearchApi _searchApi;
  // final StacksApi _stacksApi;
  // final TrashApi _trashApi;

  AssetApiRepository(this._apiService);
  // AssetApiRepository(this._api, this._searchApi, this._stacksApi, this._trashApi);

  AssetsApi get _api => _apiService.assetsApi;
  SearchApi get _searchApi => _apiService.searchApi;
  StacksApi get _stacksApi => _apiService.stacksApi;
  TrashApi get _trashApi => _apiService.trashApi;
  // #pizcloud

  Future<Asset> update(String id, {String? description}) async {
    // pizcloud
    // final response = await checkNull(_api.updateAsset(id, UpdateAssetDto(description: description)));
    final response = await checkNullWithService(
      _apiService,
      () => _api.updateAsset(id, UpdateAssetDto(description: description)),
    );
    // #pizcloud
    return Asset.remote(response);
  }

  Future<List<Asset>> search({List<String> personIds = const []}) async {
    // TODO this always fetches all assets, change API and usage to actually do pagination
    final List<Asset> result = [];
    bool hasNext = true;
    int currentPage = 1;
    while (hasNext) {
      // pizcloud
      // final response = await checkNull(
      //   _searchApi.searchAssets(MetadataSearchDto(personIds: personIds, page: currentPage, size: 1000)),
      // );
      final response = await checkNullWithService(
        _apiService,
        () => _searchApi.searchAssets(MetadataSearchDto(personIds: personIds, page: currentPage, size: 1000)),
      );
      // #pizcloud
      result.addAll(response.assets.items.map(Asset.remote));
      hasNext = response.assets.nextPage != null;
      currentPage++;
    }
    return result;
  }

  Future<void> delete(List<String> ids, bool force) async {
    // return _api.deleteAssets(AssetBulkDeleteDto(ids: ids, force: force));
    ensureEndpoint(_apiService); // pizcloud
    return _api.deleteAssets(AssetBulkDeleteDto(ids: ids, force: force));
  }

  Future<void> restoreTrash(List<String> ids) async {
    // await _trashApi.restoreAssets(BulkIdsDto(ids: ids));
    ensureEndpoint(_apiService); // pizcloud
    await _trashApi.restoreAssets(BulkIdsDto(ids: ids));
  }

  Future<void> updateVisibility(List<String> ids, AssetVisibilityEnum visibility) async {
    // return _api.updateAssets(AssetBulkUpdateDto(ids: ids, visibility: _mapVisibility(visibility)));
    ensureEndpoint(_apiService); // pizcloud
    return _api.updateAssets(AssetBulkUpdateDto(ids: ids, visibility: _mapVisibility(visibility)));
  }

  Future<void> updateFavorite(List<String> ids, bool isFavorite) async {
    // return _api.updateAssets(AssetBulkUpdateDto(ids: ids, isFavorite: isFavorite));
    ensureEndpoint(_apiService); // pizcloud
    return _api.updateAssets(AssetBulkUpdateDto(ids: ids, isFavorite: isFavorite));
  }

  Future<void> updateLocation(List<String> ids, LatLng location) async {
    // return _api.updateAssets(AssetBulkUpdateDto(ids: ids, latitude: location.latitude, longitude: location.longitude));
    ensureEndpoint(_apiService); // pizcloud
    return _api.updateAssets(AssetBulkUpdateDto(ids: ids, latitude: location.latitude, longitude: location.longitude));
  }

  Future<void> updateDateTime(List<String> ids, DateTime dateTime) async {
    // return _api.updateAssets(AssetBulkUpdateDto(ids: ids, dateTimeOriginal: dateTime.toIso8601String()));
    ensureEndpoint(_apiService); // pizcloud
    return _api.updateAssets(AssetBulkUpdateDto(ids: ids, dateTimeOriginal: dateTime.toIso8601String()));
  }

  Future<StackResponse> stack(List<String> ids) async {
    // pizcloud
    // final responseDto = await checkNull(_stacksApi.createStack(StackCreateDto(assetIds: ids)));
    final responseDto = await checkNullWithService(
      _apiService,
      () => _stacksApi.createStack(StackCreateDto(assetIds: ids)),
    );
    // #pizcloud

    return responseDto.toStack();
  }

  Future<void> unStack(List<String> ids) async {
    // return _stacksApi.deleteStacks(BulkIdsDto(ids: ids));
    ensureEndpoint(_apiService); // pizcloud
    return _stacksApi.deleteStacks(BulkIdsDto(ids: ids));
  }

  Future<Response> downloadAsset(String id) {
    // return _api.downloadAssetWithHttpInfo(id);
    ensureEndpoint(_apiService); // pizcloud
    return _api.downloadAssetWithHttpInfo(id);
  }

  _mapVisibility(AssetVisibilityEnum visibility) => switch (visibility) {
    AssetVisibilityEnum.timeline => AssetVisibility.timeline,
    AssetVisibilityEnum.hidden => AssetVisibility.hidden,
    AssetVisibilityEnum.locked => AssetVisibility.locked,
    AssetVisibilityEnum.archive => AssetVisibility.archive,
  };

  Future<String?> getAssetMIMEType(String assetId) async {
    // final response = await checkNull(_api.getAssetInfo(assetId)); // pizcloud
    final response = await checkNullWithService(_apiService, () => _api.getAssetInfo(assetId)); // pizcloud

    // we need to get the MIME of the thumbnail once that gets added to the API
    return response.originalMimeType;
  }

  Future<void> updateDescription(String assetId, String description) {
    // return _api.updateAsset(assetId, UpdateAssetDto(description: description));
    ensureEndpoint(_apiService); // pizcloud
    return _api.updateAsset(assetId, UpdateAssetDto(description: description));
  }
}

extension on StackResponseDto {
  StackResponse toStack() {
    return StackResponse(id: id, primaryAssetId: primaryAssetId, assetIds: assets.map((asset) => asset.id).toList());
  }
}
