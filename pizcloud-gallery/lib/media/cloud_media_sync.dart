import 'media_models.dart';
import 'media_repository.dart';

abstract class CloudMediaClient {
  Future<CloudMediaPage> fetchMedia({
    String? pageToken,
    int pageSize = 200,
    DateTime? since,
  });
}

class CloudMediaPage {
  const CloudMediaPage({
    required this.items,
    this.nextPageToken,
  });

  final List<RemoteMediaItem> items;
  final String? nextPageToken;
}

class CloudMediaSyncService {
  CloudMediaSyncService({
    required MediaRepository repository,
    required CloudMediaClient client,
  })  : _repository = repository,
        _client = client;

  final MediaRepository _repository;
  final CloudMediaClient _client;

  Future<int> syncAll({
    int pageSize = 200,
    DateTime? since,
  }) async {
    String? token;
    int totalUpserted = 0;
    do {
      final page = await _client.fetchMedia(
        pageToken: token,
        pageSize: pageSize,
        since: since,
      );
      if (page.items.isNotEmpty) {
        final now = DateTime.now();
        final items =
            page.items.map((item) => item.toMediaItem(updatedAt: now)).toList();
        totalUpserted += await _repository.upsertRemoteItems(items);
      }
      token = page.nextPageToken;
    } while (token != null);

    return totalUpserted;
  }
}
