import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/services/duplicates.service.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/string_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_viewer.page.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail.widget.dart';
import 'package:immich_mobile/providers/infrastructure/duplicates.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/bytes_units.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:openapi/api.dart';

final _reviewDuplicatesBootstrapProvider = FutureProvider.autoDispose<void>((ref) async {
  await ref.read(serverInfoProvider.notifier).getServerFeatures();
});

@RoutePage()
class DriftReviewDuplicatesPage extends ConsumerWidget {
  const DriftReviewDuplicatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(_reviewDuplicatesBootstrapProvider);

    final useTrash = ref.watch(serverInfoProvider.select((value) => value.serverFeatures.trash));
    final duplicateDetectionEnabled = ref.watch(
      serverInfoProvider.select((value) => value.serverFeatures.duplicateDetection),
    );
    final state = duplicateDetectionEnabled ? ref.watch(duplicatesProvider) : null;
    final groups = state?.groups.valueOrNull ?? const <DuplicateGroup>[];
    final hasGroups = groups.isNotEmpty;
    final isMutating = state?.isMutating ?? false;
    final removableAssetsCount = _getRemovableAssetsCount(groups);
    final initialGroupCount = state?.initialGroupCount ?? 0;
    final resolvedGroupCount = (initialGroupCount - groups.length).clamp(0, initialGroupCount).toInt();
    final progressValue = initialGroupCount <= 0 ? 0.0 : resolvedGroupCount / initialGroupCount;

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text('review_duplicates'.t(context: context)),
        leading: IconButton(
          onPressed: () => context.maybePop(),
          icon: Icon(context.platformIcons.back),
          splashRadius: 24,
        ),
        trailingActions: [
          IconButton(
            onPressed: !duplicateDetectionEnabled || isMutating
                ? null
                : () => ref.read(duplicatesProvider.notifier).load(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'refresh'.tr(),
          ),
        ],
        material: (_, __) => MaterialAppBarData(centerTitle: false),
      ),
      body: duplicateDetectionEnabled
          ? state!.groups.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _DuplicateErrorState(
                message: error.toString(),
                onRetry: () => ref.read(duplicatesProvider.notifier).load(),
              ),
              data: (groups) {
                if (groups.isEmpty) {
                  return const _DuplicateEmptyState();
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _DuplicateBulkActionsCard(
                        useTrash: useTrash,
                        isKeepingAll: state.isKeepingAll,
                        isDeduplicatingAll: state.isDeduplicatingAll,
                        isBusy: state.isMutating,
                        removableCount: removableAssetsCount,
                        hasGroups: hasGroups,
                        resolvedGroupCount: resolvedGroupCount,
                        totalGroupCount: initialGroupCount,
                        progressValue: progressValue,
                        onDeduplicateAll: () =>
                            _onDeduplicateAll(context: context, ref: ref, groups: groups, useTrash: useTrash),
                        onKeepAll: () => _onKeepAll(context: context, ref: ref, groups: groups),
                      );
                    }

                    final group = groups[index - 1];
                    final selectedKeepAssetIds = state.keepSelectionByGroupId[group.duplicateId] ?? const <String>{};
                    final trashCount = _getGroupTrashCount(group, selectedKeepAssetIds);

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _DuplicateGroupCard(
                        index: index - 1,
                        group: group,
                        selectedKeepAssetIds: selectedKeepAssetIds,
                        isResolving: state.resolvingGroupIds.contains(group.duplicateId),
                        isStacking: state.stackingGroupIds.contains(group.duplicateId),
                        isBusy: state.isMutating,
                        useTrash: useTrash,
                        trashCount: trashCount,
                        onKeepSelected: (assetId) {
                          ref.read(duplicatesProvider.notifier).setKeepSelection(group.duplicateId, assetId);
                        },
                        onSelectKeepAll: () {
                          ref.read(duplicatesProvider.notifier).selectKeepAll(group.duplicateId);
                        },
                        onSelectTrashAll: () {
                          ref.read(duplicatesProvider.notifier).selectTrashAll(group.duplicateId);
                        },
                        onResolve: () => _onResolveGroup(
                          context: context,
                          ref: ref,
                          group: group,
                          useTrash: useTrash,
                          selectedKeepAssetIds: selectedKeepAssetIds,
                        ),
                        onStack: () => _onStackGroup(context: context, ref: ref, group: group),
                        onOpenAsset: (assetIndex) =>
                            _openAssetViewer(context: context, ref: ref, group: group, index: assetIndex),
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemCount: groups.length + 1,
                );
              },
            )
          : const _DuplicateFeatureDisabledState(),
    );
  }

  Future<void> _onResolveGroup({
    required BuildContext context,
    required WidgetRef ref,
    required DuplicateGroup group,
    required bool useTrash,
    required Set<String> selectedKeepAssetIds,
  }) async {
    final removableCount = _getGroupTrashCount(group, selectedKeepAssetIds);
    final shouldProceed = await _showGroupResolveConfirm(
      context: context,
      useTrash: useTrash,
      removableCount: removableCount,
      groupAssetCount: group.assets.length,
    );
    if (!shouldProceed || !context.mounted) {
      return;
    }

    try {
      await ref.read(duplicatesProvider.notifier).resolveGroup(group.duplicateId, useTrash: useTrash);

      if (!context.mounted) {
        return;
      }
      ImmichToast.show(
        context: context,
        msg: 'resolve_duplicates'.t(context: context),
        toastType: ToastType.success,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ImmichToast.show(context: context, msg: _getDeleteErrorMessage(context, error), toastType: ToastType.error);
    }
  }

  Future<void> _onStackGroup({
    required BuildContext context,
    required WidgetRef ref,
    required DuplicateGroup group,
  }) async {
    if (group.assets.length <= 1) {
      return;
    }

    try {
      await ref.read(duplicatesProvider.notifier).stackGroup(group.duplicateId);
      if (!context.mounted) {
        return;
      }

      ImmichToast.show(
        context: context,
        msg: 'stacked_assets_count'.t(context: context, args: {'count': group.assets.length}),
        toastType: ToastType.success,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ImmichToast.show(context: context, msg: _getStackErrorMessage(context, error), toastType: ToastType.error);
    }
  }

  Future<void> _onDeduplicateAll({
    required BuildContext context,
    required WidgetRef ref,
    required List<DuplicateGroup> groups,
    required bool useTrash,
  }) async {
    final removableCount = _getRemovableAssetsCount(groups);
    if (groups.isEmpty || removableCount <= 0) {
      return;
    }

    final confirmMessageKey = useTrash ? 'bulk_trash_duplicates_confirmation' : 'bulk_delete_duplicates_confirmation';
    final shouldProceed = await _showConfirmDialog(
      context: context,
      title: useTrash ? 'to_trash'.t(context: context) : 'delete_permanently'.t(context: context),
      message: confirmMessageKey.t(context: context, args: {'count': removableCount}),
    );
    if (!shouldProceed || !context.mounted) {
      return;
    }

    try {
      await ref.read(duplicatesProvider.notifier).deduplicateAll(useTrash: useTrash);
      if (!context.mounted) {
        return;
      }

      final successMessageKey = useTrash ? 'assets_moved_to_trash_count' : 'assets_permanently_deleted_count';
      ImmichToast.show(
        context: context,
        msg: successMessageKey.t(context: context, args: {'count': removableCount}),
        toastType: ToastType.success,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ImmichToast.show(context: context, msg: _getDeleteErrorMessage(context, error), toastType: ToastType.error);
    }
  }

  Future<void> _onKeepAll({
    required BuildContext context,
    required WidgetRef ref,
    required List<DuplicateGroup> groups,
  }) async {
    if (groups.isEmpty) {
      return;
    }

    final shouldProceed = await _showConfirmDialog(
      context: context,
      title: 'keep_all'.t(context: context),
      message: 'bulk_keep_duplicates_confirmation'.t(context: context, args: {'count': groups.length}),
    );
    if (!shouldProceed || !context.mounted) {
      return;
    }

    try {
      await ref.read(duplicatesProvider.notifier).keepAll();
      if (!context.mounted) {
        return;
      }
      ImmichToast.show(
        context: context,
        msg: 'resolved_all_duplicates'.t(context: context),
        toastType: ToastType.success,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ImmichToast.show(context: context, msg: _getDeleteErrorMessage(context, error), toastType: ToastType.error);
    }
  }

  Future<void> _openAssetViewer({
    required BuildContext context,
    required WidgetRef ref,
    required DuplicateGroup group,
    required int index,
  }) async {
    final assets = group.assets.map((item) => item.asset).toList(growable: false);
    final timelineService = ref.read(timelineFactoryProvider).fromAssets(assets, TimelineOrigin.search);
    AssetViewer.setAsset(ref, assets[index]);

    try {
      await context.pushRoute(AssetViewerRoute(initialIndex: index, timelineService: timelineService));
    } finally {
      await timelineService.dispose();
    }
  }
}

int _getRemovableAssetsCount(List<DuplicateGroup> groups) {
  return groups.fold<int>(0, (count, group) => count + (group.assets.length > 1 ? group.assets.length - 1 : 0));
}

int _getGroupTrashCount(DuplicateGroup group, Set<String> selectedKeepAssetIds) {
  return group.assets.where((item) => !selectedKeepAssetIds.contains(item.asset.id)).length;
}

Future<bool> _showGroupResolveConfirm({
  required BuildContext context,
  required bool useTrash,
  required int removableCount,
  required int groupAssetCount,
}) {
  if (removableCount <= 0) {
    return _showConfirmDialog(
      context: context,
      title: 'resolve_duplicates'.t(context: context),
      message: 'group_resolve_without_delete_confirmation'.t(context: context),
    );
  }

  final isAllInGroup = removableCount == groupAssetCount;
  final messageKey = switch ((useTrash, isAllInGroup)) {
    (true, true) => 'group_trash_all_duplicates_confirmation',
    (true, false) => 'group_trash_duplicates_confirmation',
    (false, true) => 'group_delete_all_duplicates_confirmation',
    (false, false) => 'group_delete_duplicates_confirmation',
  };

  return _showConfirmDialog(
    context: context,
    title: useTrash ? 'to_trash'.t(context: context) : 'delete_permanently'.t(context: context),
    message: messageKey.t(context: context, args: {'count': removableCount}),
  );
}

class _DuplicateGroupCard extends StatelessWidget {
  final int index;
  final DuplicateGroup group;
  final Set<String> selectedKeepAssetIds;
  final bool isResolving;
  final bool isStacking;
  final bool isBusy;
  final bool useTrash;
  final int trashCount;
  final ValueChanged<String> onKeepSelected;
  final VoidCallback onSelectKeepAll;
  final VoidCallback onSelectTrashAll;
  final Future<void> Function() onResolve;
  final Future<void> Function() onStack;
  final ValueChanged<int> onOpenAsset;

  const _DuplicateGroupCard({
    required this.index,
    required this.group,
    required this.selectedKeepAssetIds,
    required this.isResolving,
    required this.isStacking,
    required this.isBusy,
    required this.useTrash,
    required this.trashCount,
    required this.onKeepSelected,
    required this.onSelectKeepAll,
    required this.onSelectTrashAll,
    required this.onResolve,
    required this.onStack,
    required this.onOpenAsset,
  });

  @override
  Widget build(BuildContext context) {
    final selectionEnabled = !isBusy && !isResolving && !isStacking;
    final canResolve = !isBusy && !isResolving;
    final canStack = !isBusy && !isStacking;
    final keepCount = group.assets.length - trashCount;

    return Container(
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(color: context.colorScheme.outline.withAlpha(26)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.colorScheme.primary.withAlpha(22),
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                  ),
                  child: Text(
                    '#${index + 1}',
                    style: context.textTheme.labelLarge?.copyWith(
                      color: context.primaryColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'assets_count'.t(context: context, args: {'count': group.assets.length}),
                  style: context.textTheme.labelLarge?.copyWith(color: context.colorScheme.onSurface.withAlpha(170)),
                ),
                const Spacer(),
                Text(
                  'assets_count'.t(context: context, args: {'count': trashCount}),
                  style: context.textTheme.labelSmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(150)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: selectionEnabled ? onSelectKeepAll : null,
                  icon: const Icon(Icons.done_all_rounded, size: 16),
                  label: Text('select_keep_all'.t(context: context)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: selectionEnabled ? onSelectTrashAll : null,
                  icon: const Icon(Icons.remove_done_rounded, size: 16),
                  label: Text('select_trash_all'.t(context: context)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...List.generate(group.assets.length, (assetIndex) {
              final item = group.assets[assetIndex];
              final isSelected = selectedKeepAssetIds.contains(item.asset.id);
              return Padding(
                padding: EdgeInsets.only(bottom: assetIndex == group.assets.length - 1 ? 0 : 8),
                child: _DuplicateAssetTile(
                  item: item,
                  selected: isSelected,
                  selectable: selectionEnabled,
                  onSelect: () => onKeepSelected(item.asset.id),
                  onOpen: () => onOpenAsset(assetIndex),
                ),
              );
            }),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canStack && group.assets.length > 1 ? onStack : null,
                    icon: isStacking
                        ? SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: context.colorScheme.primary),
                          )
                        : const Icon(Icons.photo_library_outlined),
                    label: Text('stack'.t(context: context)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canResolve ? onResolve : null,
                    icon: isResolving
                        ? SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: context.colorScheme.onPrimary),
                          )
                        : Icon(
                            trashCount == 0
                                ? Icons.check_circle_outline_rounded
                                : (useTrash ? Icons.delete_outline_rounded : Icons.delete_forever_outlined),
                          ),
                    label: Text(
                      trashCount == 0
                          ? 'keep_all'.t(context: context)
                          : (useTrash ? 'to_trash'.t(context: context) : 'delete_permanently'.t(context: context)),
                    ),
                  ),
                ),
              ],
            ),
            if (group.assets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '$keepCount/${group.assets.length}',
                  style: context.textTheme.labelSmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(145)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DuplicateBulkActionsCard extends StatelessWidget {
  final bool useTrash;
  final bool isKeepingAll;
  final bool isDeduplicatingAll;
  final bool isBusy;
  final bool hasGroups;
  final int removableCount;
  final int resolvedGroupCount;
  final int totalGroupCount;
  final double progressValue;
  final Future<void> Function() onDeduplicateAll;
  final Future<void> Function() onKeepAll;

  const _DuplicateBulkActionsCard({
    required this.useTrash,
    required this.isKeepingAll,
    required this.isDeduplicatingAll,
    required this.isBusy,
    required this.hasGroups,
    required this.removableCount,
    required this.resolvedGroupCount,
    required this.totalGroupCount,
    required this.progressValue,
    required this.onDeduplicateAll,
    required this.onKeepAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        gradient: LinearGradient(
          colors: [context.colorScheme.primary.withAlpha(16), context.colorScheme.primary.withAlpha(8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: context.colorScheme.primary.withAlpha(38)),
        boxShadow: [
          BoxShadow(color: context.colorScheme.shadow.withAlpha(18), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'duplicates_description'.t(context: context),
              style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurface.withAlpha(165)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '$resolvedGroupCount/$totalGroupCount',
                  style: context.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'assets_count'.t(context: context, args: {'count': removableCount}),
                  style: context.textTheme.labelMedium?.copyWith(color: context.colorScheme.onSurface.withAlpha(150)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: progressValue.clamp(0.0, 1.0),
                backgroundColor: context.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: isBusy || removableCount <= 0 ? null : onDeduplicateAll,
                  icon: isDeduplicatingAll
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: context.colorScheme.onPrimary),
                        )
                      : Icon(useTrash ? Icons.delete_outline_rounded : Icons.delete_forever_outlined),
                  label: Text('deduplicate_all'.t(context: context)),
                ),
                OutlinedButton.icon(
                  onPressed: isBusy || !hasGroups ? null : onKeepAll,
                  icon: isKeepingAll
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: context.colorScheme.primary),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text('keep_all'.t(context: context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DuplicateAssetTile extends StatelessWidget {
  final DuplicateAssetItem item;
  final bool selected;
  final bool selectable;
  final VoidCallback onSelect;
  final VoidCallback onOpen;

  const _DuplicateAssetTile({
    required this.item,
    required this.selected,
    required this.selectable,
    required this.onSelect,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final subtitlePieces = <String>[
      if (item.fileSizeInBytes != null) formatBytes(item.fileSizeInBytes!),
      if (item.asset.width != null && item.asset.height != null) '${item.asset.width}×${item.asset.height}',
      DateFormat.yMMMd().format(item.asset.createdAt.toLocal()),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? context.colorScheme.primary.withAlpha(16) : context.colorScheme.surface,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(
          color: selected ? context.colorScheme.primary.withAlpha(150) : context.colorScheme.outline.withAlpha(24),
          width: selected ? 1.2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            InkWell(
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              onTap: onOpen,
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(10)),
                child: SizedBox(width: 58, height: 58, child: Thumbnail.fromAsset(asset: item.asset)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.asset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitlePieces.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(150)),
                  ),
                ],
              ),
            ),
            InkWell(
              borderRadius: const BorderRadius.all(Radius.circular(20)),
              onTap: selectable ? onSelect : null,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selectable
                      ? (selected ? context.primaryColor : context.colorScheme.onSurface.withAlpha(160))
                      : context.colorScheme.onSurface.withAlpha(96),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DuplicateEmptyState extends StatelessWidget {
  const _DuplicateEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_none_rounded, size: 34, color: context.colorScheme.onSurface.withAlpha(140)),
            const SizedBox(height: 12),
            Text(
              'no_duplicates_found'.t(context: context),
              textAlign: TextAlign.center,
              style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _DuplicateFeatureDisabledState extends StatelessWidget {
  const _DuplicateFeatureDisabledState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.disabled_visible_outlined, size: 34, color: context.colorScheme.onSurface.withAlpha(140)),
            const SizedBox(height: 12),
            Text(
              'disabled'.t(context: context),
              style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'admin.machine_learning_duplicate_detection_setting_description'.t(context: context),
              textAlign: TextAlign.center,
              style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(150)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DuplicateErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _DuplicateErrorState({required this.message, required this.onRetry});

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

Future<bool> _showConfirmDialog({required BuildContext context, required String title, required String message}) async {
  final shouldProceed = await showPlatformDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('cancel'.t(context: dialogContext)),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(
            'confirm'.t(context: dialogContext),
            style: TextStyle(color: dialogContext.colorScheme.error),
          ),
        ),
      ],
    ),
  );
  return shouldProceed ?? false;
}

String _getDeleteErrorMessage(BuildContext context, Object error) {
  if (error is! ApiException) {
    return 'scaffold_body_error_occurred'.t(context: context);
  }

  final String? parsedMessage = tryJsonDecode(error.message)?['message'] as String?;
  final String? serverMessage = parsedMessage ?? error.message;
  final String normalized = (serverMessage ?? '').toLowerCase();

  if (error.code == 403) {
    if (normalized.contains('read-only')) {
      return 'errors.delete_error_demo_account_read_only'.t(context: context);
    }

    return 'errors.delete_error_forbidden'.t(context: context);
  }

  if (serverMessage != null && serverMessage.trim().isNotEmpty) {
    return serverMessage;
  }

  return 'scaffold_body_error_occurred'.t(context: context);
}

String _getStackErrorMessage(BuildContext context, Object error) {
  if (error is! ApiException) {
    return 'errors.failed_to_stack_assets'.t(context: context);
  }

  final String? parsedMessage = tryJsonDecode(error.message)?['message'] as String?;
  final String? serverMessage = parsedMessage ?? error.message;
  final String normalized = (serverMessage ?? '').toLowerCase();

  if (error.code == 403) {
    if (normalized.contains('read-only')) {
      return 'errors.delete_error_demo_account_read_only'.t(context: context);
    }

    return 'errors.delete_error_forbidden'.t(context: context);
  }

  if (serverMessage != null && serverMessage.trim().isNotEmpty) {
    return serverMessage;
  }

  return 'errors.failed_to_stack_assets'.t(context: context);
}
