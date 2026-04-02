import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/services/large_files.service.dart';
import 'package:immich_mobile/providers/infrastructure/search.provider.dart';

const largeFilesMinFileSizeInBytes = 0;

final largeFilesServiceProvider = Provider<LargeFilesService>(
  (ref) => LargeFilesService(ref.watch(searchApiRepositoryProvider)),
);

final largeFilesProvider = FutureProvider.autoDispose<List<LargeFileAssetItem>>(
  (ref) => ref.watch(largeFilesServiceProvider).getLargeFileAssets(minFileSize: largeFilesMinFileSizeInBytes),
);
