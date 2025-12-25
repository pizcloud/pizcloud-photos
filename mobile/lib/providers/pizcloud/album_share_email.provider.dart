import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/pizcloud/shared_email.model.dart';
import 'package:immich_mobile/services/pizcloud/album_share_email_api.service.dart';

final albumSharedEmailsProvider = FutureProvider.family.autoDispose<List<SharedEmailDto>, String>((ref, albumId) async {
  return AlbumShareEmailApiService.getSharedEmails(albumId: albumId);
});
