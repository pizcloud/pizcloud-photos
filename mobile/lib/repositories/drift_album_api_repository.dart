import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/user.model.dart'; // pizcloud
import 'package:immich_mobile/infrastructure/utils/user.converter.dart'; // pizcloud
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/repositories/api.repository.dart';
import 'package:immich_mobile/services/api.service.dart';
// ignore: import_rule_openapi
import 'package:openapi/api.dart' hide AlbumUserRole; // pizcloud
import 'package:openapi/api.dart' as api show AlbumUserRole; // pizcloud

final driftAlbumApiRepositoryProvider = Provider(
  (ref) => DriftAlbumApiRepository(ref.watch(apiServiceProvider)),
); // pizcloud

class DriftAlbumApiRepository extends ApiRepository {
  // pizcloud
  final ApiService _apiService;
  // old: held a snapshot of AlbumsApi
  // final AlbumsApi _api;

  DriftAlbumApiRepository(this._apiService);
  // DriftAlbumApiRepository(this._api);

  AlbumsApi get _api => _apiService.albumsApi;
  // #pizcloud

  Future<RemoteAlbum> createDriftAlbum(String name, {required Iterable<String> assetIds, String? description}) async {
    // pizcloud
    // final responseDto = await checkNull(
    //   _api.createAlbum(CreateAlbumDto(albumName: name, description: description, assetIds: assetIds.toList())),
    // );
    final responseDto = await checkNullWithService(
      _apiService,
      () => _api.createAlbum(CreateAlbumDto(albumName: name, description: description, assetIds: assetIds.toList())),
    );
    // #pizcloud

    return responseDto.toRemoteAlbum();
  }

  // pizcloud
  Future<
    ({
      RemoteAlbum album,
      List<String> assetIds,
      List<AssetResponseDto> assets,
      List<({String userId, AlbumUserRole role})> users,
      List<UserDto> userDetails,
    })
  >
  getAlbumForSync(String albumId) async {
    final responseDto = await checkNullWithService(_apiService, () => _api.getAlbumInfo(albumId, withoutAssets: false));
    final assets = responseDto.assets;
    final assetIds = assets.map((asset) => asset.id).toList();
    final users = responseDto.albumUsers
        .where((albumUser) => albumUser.user.id != responseDto.ownerId)
        .map((albumUser) => (userId: albumUser.user.id, role: albumUser.role.toAlbumUserRole()))
        .toList();
    final userMap = <String, UserDto>{responseDto.owner.id: UserConverter.fromSimpleUserDto(responseDto.owner)};
    for (final albumUser in responseDto.albumUsers) {
      userMap[albumUser.user.id] = UserConverter.fromSimpleUserDto(albumUser.user);
    }
    return (
      album: responseDto.toRemoteAlbum(),
      assetIds: assetIds,
      assets: assets,
      users: users,
      userDetails: userMap.values.toList(),
    );
  }
  // #pizcloud

  Future<({List<String> removed, List<String> failed})> removeAssets(String albumId, Iterable<String> assetIds) async {
    // pizcloud
    // final response = await checkNull(_api.removeAssetFromAlbum(albumId, BulkIdsDto(ids: assetIds.toList())));
    final response = await checkNullWithService(
      _apiService,
      () => _api.removeAssetFromAlbum(albumId, BulkIdsDto(ids: assetIds.toList())),
    );
    // #pizcloud
    final List<String> removed = [], failed = [];
    for (final dto in response) {
      if (dto.success) {
        removed.add(dto.id);
      } else {
        failed.add(dto.id);
      }
    }
    return (removed: removed, failed: failed);
  }

  Future<({List<String> added, List<String> failed})> addAssets(String albumId, Iterable<String> assetIds) async {
    // pizcloud
    // final response = await checkNull(_api.addAssetsToAlbum(albumId, BulkIdsDto(ids: assetIds.toList())));
    final response = await checkNullWithService(
      _apiService,
      () => _api.addAssetsToAlbum(albumId, BulkIdsDto(ids: assetIds.toList())),
    );
    // #pizcloud
    final List<String> added = [], failed = [];
    for (final dto in response) {
      if (dto.success) {
        added.add(dto.id);
      } else {
        failed.add(dto.id);
      }
    }

    return (added: added, failed: failed);
  }

  Future<RemoteAlbum> updateAlbum(
    String albumId, {
    String? name,
    String? description,
    String? thumbnailAssetId,
    bool? isActivityEnabled,
    AlbumAssetOrder? order,
  }) async {
    AssetOrder? apiOrder;
    if (order != null) {
      apiOrder = order == AlbumAssetOrder.asc ? AssetOrder.asc : AssetOrder.desc;
    }

    // pizcloud
    // final responseDto = await checkNull(
    //   _api.updateAlbumInfo(
    //     albumId,
    //     UpdateAlbumDto(
    //       albumName: name,
    //       description: description,
    //       albumThumbnailAssetId: thumbnailAssetId,
    //       isActivityEnabled: isActivityEnabled,
    //       order: apiOrder,
    //     ),
    //   ),
    // );
    final responseDto = await checkNullWithService(
      _apiService,
      () => _api.updateAlbumInfo(
        albumId,
        UpdateAlbumDto(
          albumName: name,
          description: description,
          albumThumbnailAssetId: thumbnailAssetId,
          isActivityEnabled: isActivityEnabled,
          order: apiOrder,
        ),
      ),
    );
    // #pizcloud

    return responseDto.toRemoteAlbum();
  }

  Future<void> deleteAlbum(String albumId) {
    // return _api.deleteAlbum(albumId);
    ensureEndpoint(_apiService); // pizcloud
    return _api.deleteAlbum(albumId);
  }

  Future<RemoteAlbum> addUsers(String albumId, Iterable<String> userIds) async {
    final albumUsers = userIds.map((userId) => AlbumUserAddDto(userId: userId)).toList();
    // pizcloud
    // final response = await checkNull(_api.addUsersToAlbum(albumId, AddUsersDto(albumUsers: albumUsers)));
    final response = await checkNullWithService(
      _apiService,
      () => _api.addUsersToAlbum(albumId, AddUsersDto(albumUsers: albumUsers)),
    );
    // #pizcloud
    return response.toRemoteAlbum();
  }

  Future<void> removeUser(String albumId, {required String userId}) async {
    // await _api.removeUserFromAlbum(albumId, userId);
    ensureEndpoint(_apiService); // pizcloud
    await _api.removeUserFromAlbum(albumId, userId);
  }

  Future<bool> setActivityStatus(String albumId, bool isEnabled) async {
    // pizcloud
    // final response = await checkNull(_api.updateAlbumInfo(albumId, UpdateAlbumDto(isActivityEnabled: isEnabled)));
    final response = await checkNullWithService(
      _apiService,
      () => _api.updateAlbumInfo(albumId, UpdateAlbumDto(isActivityEnabled: isEnabled)),
    );
    // #pizcloud
    return response.isActivityEnabled;
  }
}

extension on AlbumResponseDto {
  RemoteAlbum toRemoteAlbum() {
    return RemoteAlbum(
      id: id,
      name: albumName,
      ownerId: owner.id,
      description: description,
      createdAt: createdAt,
      updatedAt: updatedAt,
      thumbnailAssetId: albumThumbnailAssetId,
      isActivityEnabled: isActivityEnabled,
      order: order == AssetOrder.asc ? AlbumAssetOrder.asc : AlbumAssetOrder.desc,
      assetCount: assetCount,
      ownerName: owner.name,
      isShared: albumUsers.length > 2,
    );
  }
}

// pizcloud
extension on api.AlbumUserRole {
  AlbumUserRole toAlbumUserRole() => switch (this) {
    api.AlbumUserRole.editor => AlbumUserRole.editor,
    api.AlbumUserRole.viewer => AlbumUserRole.viewer,
    _ => throw Exception('Unknown AlbumUserRole value: $this'),
  };
}

// #pizcloud
