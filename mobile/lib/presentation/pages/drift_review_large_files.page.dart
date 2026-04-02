import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/services/large_files.service.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_viewer.page.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail.widget.dart';
import 'package:immich_mobile/providers/infrastructure/large_files.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/bytes_units.dart';

@RoutePage()
class DriftReviewLargeFilesPage extends ConsumerWidget {
  const DriftReviewLargeFilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final largeFilesAsync = ref.watch(largeFilesProvider);

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text('review_large_files'.t(context: context)),
        leading: IconButton(
          onPressed: () => context.maybePop(),
          icon: Icon(context.platformIcons.back),
          splashRadius: 24,
        ),
        trailingActions: [
          IconButton(
            onPressed: largeFilesAsync.isLoading ? null : () => ref.invalidate(largeFilesProvider),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'refresh'.tr(),
          ),
        ],
        material: (_, __) => MaterialAppBarData(centerTitle: false),
      ),
      body: largeFilesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            _LargeFilesErrorState(message: error.toString(), onRetry: () => ref.invalidate(largeFilesProvider)),
        data: (items) {
          if (items.isEmpty) {
            return const _LargeFilesEmptyState();
          }

          final totalSizeInBytes = items.fold<int>(0, (sum, item) => sum + item.fileSizeInBytes);
          final largestFileSize = items.first.fileSizeInBytes;

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _LargeFilesSummaryCard(
                  assetCount: items.length,
                  totalSizeInBytes: totalSizeInBytes,
                  largestFileSizeInBytes: largestFileSize,
                );
              }

              final item = items[index - 1];
              return _LargeFileAssetTile(
                item: item,
                onTap: () => _openAssetViewer(context: context, ref: ref, items: items, index: index - 1),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemCount: items.length + 1,
          );
        },
      ),
    );
  }

  Future<void> _openAssetViewer({
    required BuildContext context,
    required WidgetRef ref,
    required List<LargeFileAssetItem> items,
    required int index,
  }) async {
    final assets = items.map((item) => item.asset).toList(growable: false);
    final timelineService = ref.read(timelineFactoryProvider).fromAssets(assets, TimelineOrigin.search);
    AssetViewer.setAsset(ref, assets[index]);

    try {
      await context.pushRoute(AssetViewerRoute(initialIndex: index, timelineService: timelineService));
    } finally {
      await timelineService.dispose();
      if (context.mounted) {
        ref.invalidate(largeFilesProvider);
      }
    }
  }
}

class _LargeFilesSummaryCard extends StatelessWidget {
  final int assetCount;
  final int totalSizeInBytes;
  final int largestFileSizeInBytes;

  const _LargeFilesSummaryCard({
    required this.assetCount,
    required this.totalSizeInBytes,
    required this.largestFileSizeInBytes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        gradient: LinearGradient(
          colors: [context.colorScheme.primary.withAlpha(16), context.colorScheme.primary.withAlpha(8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: context.colorScheme.primary.withAlpha(38)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'large_files_description'.t(context: context),
              style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurface.withAlpha(165)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LargeFilesMetricChip(
                  icon: Icons.photo_library_outlined,
                  text: 'assets_count'.t(context: context, args: {'count': assetCount}),
                ),
                _LargeFilesMetricChip(
                  icon: Icons.sd_storage_outlined,
                  text: '${'size'.t(context: context)}: ${formatBytes(totalSizeInBytes)}',
                ),
                _LargeFilesMetricChip(
                  icon: Icons.insert_drive_file_outlined,
                  text: '${'file_size'.t(context: context)}: ${formatBytes(largestFileSizeInBytes)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LargeFilesMetricChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _LargeFilesMetricChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.colorScheme.surface.withAlpha(168),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.all(color: context.colorScheme.outline.withAlpha(24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.primaryColor),
          const SizedBox(width: 6),
          Text(text, style: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _LargeFileAssetTile extends StatelessWidget {
  final LargeFileAssetItem item;
  final VoidCallback onTap;

  const _LargeFileAssetTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final subtitlePieces = <String>[
      formatBytes(item.fileSizeInBytes),
      if (item.asset.width != null && item.asset.height != null) '${item.asset.width}×${item.asset.height}',
      DateFormat.yMMMd().format(item.asset.createdAt.toLocal()),
    ];

    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: context.colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: context.colorScheme.outline.withAlpha(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(10)),
                child: SizedBox(width: 68, height: 68, child: Thumbnail.fromAsset(asset: item.asset)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.asset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitlePieces.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(150)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: context.colorScheme.onSurface.withAlpha(165)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LargeFilesEmptyState extends StatelessWidget {
  const _LargeFilesEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sd_storage_outlined, size: 34, color: context.colorScheme.onSurface.withAlpha(140)),
            const SizedBox(height: 12),
            Text(
              'no_assets_to_show'.t(context: context),
              textAlign: TextAlign.center,
              style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _LargeFilesErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LargeFilesErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 34, color: context.colorScheme.error),
            const SizedBox(height: 10),
            Text(
              'error'.t(context: context),
              style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(150)),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('refresh'.t(context: context)),
            ),
          ],
        ),
      ),
    );
  }
}
