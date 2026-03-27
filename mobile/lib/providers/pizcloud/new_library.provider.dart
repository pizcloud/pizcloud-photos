import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:pizcloud_gallery/pizcloud_gallery.dart';

import 'package:immich_mobile/presentation/pages/pizcloud/new_library_media_mapper.dart';
import 'package:immich_mobile/presentation/pages/pizcloud/new_library_timeline_gallery_source.dart';

final newLibraryReselectSignalProvider = StateProvider<int>((ref) => 0);

class NewLibraryLocateRequest {
  const NewLibraryLocateRequest({required this.mediaItemId, required this.requestId});

  final String mediaItemId;
  final int requestId;
}

class NewLibraryLocateRequestNotifier extends StateNotifier<NewLibraryLocateRequest?> {
  NewLibraryLocateRequestNotifier() : super(null);
  static const Duration _requestTtl = Duration(seconds: 30);

  int _nextRequestId = 0;
  Timer? _requestExpiryTimer;

  bool queueAsset(BaseAsset asset) {
    final String? mediaItemId = buildNewLibraryMediaItemId(asset);
    if (mediaItemId == null) {
      return false;
    }

    return queueMediaItemId(mediaItemId);
  }

  bool queueMediaItemId(String mediaItemId) {
    final String normalized = mediaItemId.trim();
    if (normalized.isEmpty) {
      return false;
    }

    final requestId = ++_nextRequestId;
    state = NewLibraryLocateRequest(mediaItemId: normalized, requestId: requestId);
    _armExpiryTimer(requestId);
    return true;
  }

  void clear() {
    _requestExpiryTimer?.cancel();
    _requestExpiryTimer = null;
    state = null;
  }

  void clearIfMatches(int requestId) {
    if (state?.requestId == requestId) {
      clear();
    }
  }

  void _armExpiryTimer(int requestId) {
    _requestExpiryTimer?.cancel();
    _requestExpiryTimer = Timer(_requestTtl, () {
      if (state?.requestId == requestId) {
        state = null;
      }
      _requestExpiryTimer = null;
    });
  }

  @override
  void dispose() {
    _requestExpiryTimer?.cancel();
    super.dispose();
  }
}

final newLibraryLocateRequestProvider =
    StateNotifierProvider<NewLibraryLocateRequestNotifier, NewLibraryLocateRequest?>((ref) {
      return NewLibraryLocateRequestNotifier();
    });

final newLibraryTimelineQueryProvider = Provider.autoDispose<TimelineQuery>((ref) {
  final users = ref.watch(timelineUsersProvider).valueOrNull ?? const <String>[];
  final repository = ref.watch(timelineRepositoryProvider);
  final groupBy = ref.watch(timelineFactoryProvider).groupBy;

  return repository.main(users, groupBy);
});

final newLibraryNeedsUploadedAtRepairProvider = FutureProvider.autoDispose<bool>((ref) async {
  final db = ref.watch(driftProvider);
  final row = await db
      .customSelect(
        'SELECT 1 AS needs_repair FROM remote_asset_entity WHERE uploaded_at IS NULL LIMIT 1',
        readsFrom: {db.remoteAssetEntity},
      )
      .getSingleOrNull();
  return row != null;
});

final newLibraryGallerySourceProvider = Provider.autoDispose<TimelineGallerySource>((ref) {
  // Configure auth headers for all pizcloud_gallery network loaders.
  PizGalleryAuthContext.configure(headersResolver: ApiService.getRequestHeaders);

  final query = ref.watch(newLibraryTimelineQueryProvider);
  final source = TimelineGallerySource(query: query);

  ref.onDispose(source.dispose);
  return source;
});
