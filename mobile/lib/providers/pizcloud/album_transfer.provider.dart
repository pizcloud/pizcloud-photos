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

List<String> ownedAlbumIds({
  required Iterable<RemoteAlbum> albums,
  required String ownerId,
}) {
  return albums.where((album) => album.ownerId == ownerId).map((album) => album.id).toList(growable: false);
}
