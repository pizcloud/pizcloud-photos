import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:pizcloud_gallery/pizcloud_gallery.dart';

import 'package:immich_mobile/presentation/pages/pizcloud/new_library_timeline_gallery_source.dart';

final newLibraryReselectSignalProvider = StateProvider<int>((ref) => 0);

final newLibraryTimelineQueryProvider = Provider.autoDispose<TimelineQuery>((ref) {
  final users = ref.watch(timelineUsersProvider).valueOrNull ?? const <String>[];
  final repository = ref.watch(timelineRepositoryProvider);
  final groupBy = ref.watch(timelineFactoryProvider).groupBy;

  return repository.main(users, groupBy);
});

final newLibraryGallerySourceProvider = Provider.autoDispose<TimelineGallerySource>((ref) {
  // Configure auth headers for all pizcloud_gallery network loaders.
  PizGalleryAuthContext.configure(headersResolver: ApiService.getRequestHeaders);

  final query = ref.watch(newLibraryTimelineQueryProvider);
  final source = TimelineGallerySource(query: query);

  ref.onDispose(source.dispose);
  return source;
});
