import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/album/pizcloud/album_transfer.model.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/services/pizcloud/album_transfer_api.service.dart';

final albumTransferByAlbumProvider = FutureProvider.family.autoDispose<AlbumTransferDto?, String>((ref, albumId) async {
  final apiService = ref.watch(apiServiceProvider);
  return AlbumTransferApiService.getAlbumTransfer(apiService, albumId);
});

final albumIncomingTransfersProvider = FutureProvider.autoDispose<List<AlbumTransferDto>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  return AlbumTransferApiService.getIncoming(apiService);
});

List<String> ownedAlbumIds({required Iterable<RemoteAlbum> albums, required String ownerId}) {
  return albums.where((album) => album.ownerId == ownerId).map((album) => album.id).toList(growable: false);
}

enum TransferRefreshReason { tabEnter, appResume, pageOpen, pullToRefresh, localMutation }

DateTime? _lastTransferRefreshAt;
Future<void>? _transferRefreshInFlight;

Duration _minIntervalFor(TransferRefreshReason reason) {
  return switch (reason) {
    TransferRefreshReason.tabEnter => const Duration(seconds: 10),
    TransferRefreshReason.appResume => const Duration(seconds: 10),
    TransferRefreshReason.pageOpen => const Duration(seconds: 10),
    TransferRefreshReason.pullToRefresh => Duration.zero,
    TransferRefreshReason.localMutation => Duration.zero,
  };
}

Future<void> refreshTransferIndicators(
  Ref ref, {
  required Iterable<RemoteAlbum> albums,
  required String ownerId,
  required TransferRefreshReason reason,
  bool force = false,
  bool includeIncoming = true,
}) {
  return _refreshTransferIndicatorsImpl(
    invalidate: (provider) => ref.invalidate(provider),
    albums: albums,
    ownerId: ownerId,
    reason: reason,
    force: force,
    includeIncoming: includeIncoming,
  );
}

Future<void> refreshTransferIndicatorsForWidget(
  WidgetRef ref, {
  required Iterable<RemoteAlbum> albums,
  required String ownerId,
  required TransferRefreshReason reason,
  bool force = false,
  bool includeIncoming = true,
}) {
  return _refreshTransferIndicatorsImpl(
    invalidate: (provider) => ref.invalidate(provider),
    albums: albums,
    ownerId: ownerId,
    reason: reason,
    force: force,
    includeIncoming: includeIncoming,
  );
}

Future<void> _refreshTransferIndicatorsImpl({
  required void Function(dynamic provider) invalidate,
  required Iterable<RemoteAlbum> albums,
  required String ownerId,
  required TransferRefreshReason reason,
  required bool force,
  required bool includeIncoming,
}) async {
  if (ownerId.isEmpty) {
    return;
  }

  // Reuse an active refresh to avoid duplicate API churn from multiple triggers.
  final inFlight = _transferRefreshInFlight;
  if (inFlight != null) {
    await inFlight;
    return;
  }

  const maxStaleness = Duration(seconds: 60);
  final now = DateTime.now();
  final minInterval = _minIntervalFor(reason);
  final last = _lastTransferRefreshAt;
  final elapsed = last == null ? maxStaleness : now.difference(last);
  final shouldThrottle = !force && elapsed < minInterval && elapsed < maxStaleness;
  if (shouldThrottle) {
    return;
  }

  final refreshTask = Future<void>(() async {
    // callers invalidated incoming in each page/lifecycle entry-point.
    // if (includeIncoming) {
    //   invalidate(albumIncomingTransfersProvider);
    // }
    if (includeIncoming) {
      invalidate(albumIncomingTransfersProvider);
    }

    final albumIds = ownedAlbumIds(albums: albums, ownerId: ownerId);
    for (final albumId in albumIds) {
      invalidate(albumTransferByAlbumProvider(albumId));
    }
    _lastTransferRefreshAt = DateTime.now();
  });

  _transferRefreshInFlight = refreshTask;
  try {
    await refreshTask;
  } finally {
    if (identical(_transferRefreshInFlight, refreshTask)) {
      _transferRefreshInFlight = null;
    }
  }
}
