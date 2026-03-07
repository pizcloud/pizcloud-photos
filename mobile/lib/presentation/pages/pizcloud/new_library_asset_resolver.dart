import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/services/asset.service.dart';
import 'package:immich_mobile/infrastructure/repositories/local_asset.repository.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:pizcloud_gallery/pizcloud_gallery.dart';

import 'new_library_timeline_gallery_source.dart';

final newLibraryAssetResolverProvider = Provider.autoDispose<NewLibraryAssetResolver>((ref) {
  return NewLibraryAssetResolver(
    assetService: ref.watch(assetServiceProvider),
    localAssetRepository: ref.watch(localAssetRepository),
  );
});

class NewLibraryAssetResolver {
  const NewLibraryAssetResolver({
    required AssetService assetService,
    required DriftLocalAssetRepository localAssetRepository,
  }) : _assetService = assetService,
       _localAssetRepository = localAssetRepository;

  final AssetService _assetService;
  final DriftLocalAssetRepository _localAssetRepository;

  BaseAsset? resolveCached(MediaItem item, {TimelineGallerySource? source}) {
    final BaseAsset? cached = source?.findAssetByMediaItemId(item.id);
    return cached;
  }

  Future<BaseAsset?> resolve(MediaItem item, {TimelineGallerySource? source}) async {
    // 1) Fast path: timeline source cache.
    final BaseAsset? cached = resolveCached(item, source: source);
    final BaseAsset? preferredCached = await _preferRemoteVersionIfAvailable(cached);
    if (preferredCached != null) {
      return preferredCached;
    }

    // 2) Resolve from stable media id patterns.
    final _ParsedMediaIdentity parsed = _ParsedMediaIdentity.fromItem(item);
    final String? remoteId = parsed.remoteId;
    if (remoteId != null && remoteId.isNotEmpty) {
      final RemoteAsset? remote = await _assetService.getRemoteAsset(remoteId);
      if (remote != null) {
        return remote;
      }
    }

    final String? localId = parsed.localId;
    if (localId != null && localId.isNotEmpty) {
      final LocalAsset? local = await _localAssetRepository.get(localId);
      if (local != null) {
        return await _preferRemoteVersionIfAvailable(local) ?? local;
      }
    }

    return null;
  }

  Future<BaseAsset?> _preferRemoteVersionIfAvailable(BaseAsset? asset) async {
    if (asset == null) {
      return null;
    }
    final String? remoteId = asset.remoteId;
    if (remoteId == null || remoteId.isEmpty) {
      return asset;
    }

    final RemoteAsset? remote = await _assetService.getRemoteAsset(remoteId);
    return remote ?? asset;
  }
}

class _ParsedMediaIdentity {
  const _ParsedMediaIdentity({this.remoteId, this.localId});

  final String? remoteId;
  final String? localId;

  factory _ParsedMediaIdentity.fromItem(MediaItem item) {
    String? remoteId;
    String? localId;
    final String id = item.id;

    if (id.startsWith('remote_')) {
      remoteId = id.substring('remote_'.length);
    } else if (id.startsWith('asset_')) {
      remoteId = id.substring('asset_'.length);
    } else if (id.startsWith('local_')) {
      localId = id.substring('local_'.length);
    } else {
      // Keep compatibility with custom id formats if host uses raw IDs.
      if (item.sourceType == MediaSourceType.remote) {
        remoteId = id;
      } else if (item.sourceType == MediaSourceType.local) {
        localId = id;
      }
    }

    localId ??= LocalDeviceMediaUri.parseOriginalAssetId(item.originalUrl);
    return _ParsedMediaIdentity(remoteId: _normalize(remoteId), localId: _normalize(localId));
  }

  static String? _normalize(String? value) {
    if (value == null) {
      return null;
    }
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
