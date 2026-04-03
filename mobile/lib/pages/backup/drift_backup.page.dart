import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/features/walkthrough/first_login_walkthrough_keys.dart'; // pizcloud
import 'package:immich_mobile/features/walkthrough/first_login_walkthrough_provider.dart'; // pizcloud
import 'package:immich_mobile/generated/intl_keys.g.dart';
import 'package:immich_mobile/presentation/widgets/backup/backup_toggle_button.widget.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/backup_album.provider.dart';
import 'package:immich_mobile/providers/backup/drift_backup.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart'; // pizcloud
import 'package:immich_mobile/providers/sync_status.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/backup/backup_info_card.dart';
import 'package:logging/logging.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

@RoutePage()
class DriftBackupPage extends ConsumerStatefulWidget {
  const DriftBackupPage({super.key});

  @override
  ConsumerState<DriftBackupPage> createState() => _DriftBackupPageState();
}

class _DriftBackupPageState extends ConsumerState<DriftBackupPage> {
  bool? syncSuccess;
  // pizcloud
  bool _showLowBatteryWarning = false;
  Timer? _powerStatusPollingTimer;

  Future<void> _refreshLowBatteryWarning() async {
    final shouldShow = await ref.read(backgroundWorkerFgServiceProvider).isLowBatteryWarningRequired();
    if (!mounted || shouldShow == _showLowBatteryWarning) {
      return;
    }

    setState(() {
      _showLowBatteryWarning = shouldShow;
    });
  }
  // #pizcloud

  @override
  void initState() {
    super.initState();

    WakelockPlus.enable();
    // pizcloud
    unawaited(_refreshLowBatteryWarning());
    _powerStatusPollingTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_refreshLowBatteryWarning());
    });
    // #pizcloud

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(driftBackupProvider.notifier).getBackupStatus(currentUser.id);

      ref.read(driftBackupProvider.notifier).updateSyncing(true);
      syncSuccess = await ref.read(backgroundSyncProvider).syncRemote();
      ref.read(driftBackupProvider.notifier).updateSyncing(false);

      if (mounted) {
        await ref.read(driftBackupProvider.notifier).getBackupStatus(currentUser.id);
      }
    });
  }

  @override
  dispose() {
    _powerStatusPollingTimer?.cancel(); // pizcloud
    super.dispose();
    WakelockPlus.disable();
  }

  @override
  Widget build(BuildContext context) {
    final selectedAlbum = ref
        .watch(backupAlbumProvider)
        .where((album) => album.backupSelection == BackupSelection.selected)
        .toList();

    final error = ref.watch(driftBackupProvider.select((p) => p.error));

    final backupNotifier = ref.read(driftBackupProvider.notifier);
    final backupSyncManager = ref.read(backgroundSyncProvider);

    Future<void> startBackup() async {
      final currentUser = Store.tryGet(StoreKey.currentUser);
      if (currentUser == null) {
        return;
      }

      if (syncSuccess == null) {
        ref.read(driftBackupProvider.notifier).updateSyncing(true);
        syncSuccess = await backupSyncManager.syncRemote();
        ref.read(driftBackupProvider.notifier).updateSyncing(false);
      }

      await backupNotifier.getBackupStatus(currentUser.id);

      if (syncSuccess == false) {
        Logger("DriftBackupPage").warning("Remote sync did not complete successfully, skipping backup");
        return;
      }
      await backupNotifier.startBackup(currentUser.id);
    }

    Future<void> stopBackup() async {
      await backupNotifier.cancel();
    }

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text("backup_controller_page_backup".t()),
        leading: IconButton(
          onPressed: () {
            context.maybePop(true);
          },
          splashRadius: 24,
          icon: Icon(context.platformIcons.back),
        ),
        trailingActions: [
          IconButton(
            onPressed: () {
              context.pushRoute(const DriftBackupOptionsRoute());
            },
            icon: Icon(context.platformIcon(material: Icons.settings_outlined, cupertino: CupertinoIcons.settings)),
            tooltip: "backup_options".t(context: context),
          ),
        ],
        material: (_, __) => MaterialAppBarData(elevation: 0),
      ),
      body: Padding(
        padding: const EdgeInsets.only(left: 16.0, right: 16, bottom: 32),
        child: ListView(
          children: [
            const SizedBox(height: 8),
            const _BackupHeroSummaryCard(),
            const SizedBox(height: 8),
            const _BackupAlbumSelectionCard(),
            if (selectedAlbum.isNotEmpty) ...[
              const SizedBox(height: 8),
              const _BackupProgressDashboardCard(),
              const SizedBox(height: 10),
              // Legacy wrapper layout for toggle (kept for comparison)
              // Container(
              //   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              //   decoration: BoxDecoration(
              //     borderRadius: const BorderRadius.all(Radius.circular(20)),
              //     border: Border.all(color: context.colorScheme.outlineVariant, width: 1),
              //     color: context.colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
              //   ),
              //   child: BackupToggleButton(
              //     onStart: () async => await startBackup(),
              //     onStop: () async {
              //       syncSuccess = null;
              //       await stopBackup();
              //     },
              //   ),
              // ),
              BackupToggleButton(
                onStart: () async => await startBackup(),
                onStop: () async {
                  syncSuccess = null;
                  await stopBackup();
                },
              ),
              // pizcloud
              if (_showLowBatteryWarning)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(Radius.circular(16)),
                      border: Border.all(color: context.colorScheme.error.withValues(alpha: 0.35)),
                      color: context.colorScheme.errorContainer.withValues(alpha: 0.2),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          context.platformIcon(
                            material: Icons.battery_alert_rounded,
                            cupertino: CupertinoIcons.battery_25,
                          ),
                          color: context.colorScheme.error,
                          fill: 1,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "backup_low_battery_warning_title".t(context: context),
                                style: context.textTheme.labelLarge?.copyWith(
                                  color: context.colorScheme.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "backup_low_battery_warning_message".t(context: context),
                                style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.error),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // #pizcloud
              switch (error) {
                BackupError.none => const SizedBox.shrink(),
                BackupError.syncFailed => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(Radius.circular(16)),
                      border: Border.all(color: context.colorScheme.error.withValues(alpha: 0.35)),
                      color: context.colorScheme.errorContainer.withValues(alpha: 0.25),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          context.platformIcon(
                            material: Icons.warning_rounded,
                            cupertino: CupertinoIcons.exclamationmark_triangle,
                          ),
                          color: context.colorScheme.error,
                          fill: 1,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            IntlKeys.backup_error_sync_failed.t(),
                            style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              },
              TextButton.icon(
                icon: Icon(context.platformIcon(material: Icons.info_outline_rounded, cupertino: CupertinoIcons.info)),
                onPressed: () => context.pushRoute(const DriftUploadDetailRoute()),
                label: Text("view_details".t(context: context)),
              ),
            ],
            // Legacy backup body layout (kept for comparison)
            // const _TotalCard(),
            // const _BackupCard(),
            // const _RemainderCard(),
          ],
        ),
      ),
    );
  }
}

class _BackupAlbumSelectionCard extends ConsumerWidget {
  const _BackupAlbumSelectionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(backupAlbumProvider);
    final selected = albums.where((album) => album.backupSelection == BackupSelection.selected).toList();
    final excluded = albums.where((album) => album.backupSelection == BackupSelection.excluded).toList();

    String selectedText() {
      if (selected.isEmpty) {
        return "backup_controller_page_none_selected".tr();
      }
      return selected
          .map((album) {
            if (album.name == "Recent" || album.name == "Recents") {
              return "${album.name} (${'all'.tr()})";
            }
            return album.name;
          })
          .join(", ");
    }

    String excludedText() {
      if (excluded.isEmpty) {
        return "";
      }
      return excluded.map((album) => album.name).join(", ");
    }

    // Legacy album selection UI (kept for comparison)
    // return Card(
    //   shape: RoundedRectangleBorder(
    //     borderRadius: const BorderRadius.all(Radius.circular(20)),
    //     side: BorderSide(color: context.colorScheme.outlineVariant, width: 1),
    //   ),
    //   elevation: 0,
    //   borderOnForeground: false,
    //   child: ListTile(
    //     minVerticalPadding: 18,
    //     title: Text("backup_controller_page_albums", style: context.textTheme.titleMedium).tr(),
    //     subtitle: ... selected/excluded album text builders ...,
    //     trailing: ElevatedButton(onPressed: () async { ... }, child: const Text("select").tr()),
    //   ),
    // );
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(color: context.colorScheme.outlineVariant, width: 1),
        gradient: LinearGradient(
          colors: [
            context.colorScheme.primary.withValues(alpha: 0.04),
            context.colorScheme.primary.withValues(alpha: 0.01),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "backup_controller_page_albums".tr(),
                  style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.tonal(
                key: walkthroughBackupSelectButtonKey, // pizcloud
                onPressed: () async {
                  ref.read(firstLoginWalkthroughControllerProvider.notifier).onBackupSelectTapped(); // pizcloud
                  await context.pushRoute(const DriftBackupAlbumSelectionRoute());
                  final currentUser = ref.read(currentUserProvider);
                  if (currentUser == null) {
                    return;
                  }
                  unawaited(ref.read(driftBackupProvider.notifier).getBackupStatus(currentUser.id));
                },
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, shape: const StadiumBorder()),
                child: const Text("select", style: TextStyle(fontWeight: FontWeight.bold)).tr(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "backup_controller_page_to_backup".tr(),
            style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceSecondary),
          ),
          const SizedBox(height: 8),
          _BackupAlbumInlineSection(
            title: "backup_controller_page_backup_selected".tr(),
            count: selected.length,
            value: selectedText(),
            valueColor: context.primaryColor,
          ),
          if (excluded.isNotEmpty) ...[
            const SizedBox(height: 8),
            _BackupAlbumInlineSection(
              title: "backup_controller_page_excluded".tr(),
              count: excluded.length,
              value: excludedText(),
              valueColor: Colors.red[300] ?? context.colorScheme.error,
            ),
          ],
        ],
      ),
    );
  }
}

class _BackupAlbumInlineSection extends StatelessWidget {
  const _BackupAlbumInlineSection({
    required this.title,
    required this.count,
    required this.value,
    required this.valueColor,
  });

  final String title;
  final int count;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        color: context.colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$title ($count)",
            style: context.textTheme.labelLarge?.copyWith(color: context.colorScheme.onSurface.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 4),
          Text(value, style: context.textTheme.labelLarge?.copyWith(color: valueColor)),
        ],
      ),
    );
  }
}

class _BackupHeroSummaryCard extends ConsumerWidget {
  const _BackupHeroSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalCount = ref.watch(driftBackupProvider.select((p) => p.totalCount));
    final backupCount = ref.watch(driftBackupProvider.select((p) => p.backupCount));
    final remainderCount = ref.watch(driftBackupProvider.select((p) => p.remainderCount));
    final syncStatus = ref.watch(syncStatusProvider);

    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(color: context.colorScheme.outlineVariant, width: 1),
        gradient: LinearGradient(
          colors: [
            context.colorScheme.primary.withValues(alpha: 0.09),
            context.colorScheme.primary.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(context.platformIcon(material: Icons.cloud_done_outlined, cupertino: CupertinoIcons.cloud_upload)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "backup_controller_page_backup".tr(),
                  style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (syncStatus.isRemoteSyncing || syncStatus.isHashing)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                    color: context.colorScheme.primary.withValues(alpha: 0.12),
                  ),
                  child: Text(
                    syncStatus.isHashing ? "preparing".t(context: context) : "syncing".t(context: context),
                    style: context.textTheme.labelSmall?.copyWith(color: context.primaryColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _BackupMetricChip(
                  title: "total".tr(),
                  value: totalCount.toString(),
                  subtitle: "backup_info_card_assets".tr(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BackupMetricChip(
                  title: "backup_controller_page_backup".tr(),
                  value: backupCount.toString(),
                  subtitle: "backup_info_card_assets".tr(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BackupMetricChip(
                  title: "backup_controller_page_remainder".tr(),
                  value: remainderCount.toString(),
                  subtitle: "backup_info_card_assets".tr(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackupMetricChip extends StatelessWidget {
  const _BackupMetricChip({required this.title, required this.value, required this.subtitle});

  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        color: context.colorScheme.surface.withValues(alpha: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelSmall?.copyWith(color: context.colorScheme.onSurface.withValues(alpha: 0.65)),
          ),
        ],
      ),
    );
  }
}

class _BackupProgressDashboardCard extends ConsumerWidget {
  const _BackupProgressDashboardCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalCount = ref.watch(driftBackupProvider.select((p) => p.totalCount));
    final backupCount = ref.watch(driftBackupProvider.select((p) => p.backupCount));
    final remainderCount = ref.watch(driftBackupProvider.select((p) => p.remainderCount));
    final syncStatus = ref.watch(syncStatusProvider);

    final progress = totalCount <= 0 ? 0.0 : (backupCount / totalCount).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(color: context.colorScheme.outlineVariant, width: 1),
        color: context.colorScheme.surfaceContainerLow.withValues(alpha: 0.35),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "backup_controller_page_remainder_sub".t(context: context),
            style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceSecondary),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: syncStatus.isRemoteSyncing ? null : progress,
              backgroundColor: context.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${"backup_controller_page_backup".tr()}: $backupCount / $totalCount",
                    style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    "${"backup_controller_page_remainder".tr()}: $remainderCount",
                    style: context.textTheme.titleSmall?.copyWith(color: context.primaryColor),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const _PreparingStatus(),
              const SizedBox(height: 2),
              ListTile(
                enableFeedback: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 0.0),
                onTap: () => context.pushRoute(const DriftBackupAssetDetailRoute()),
                title: Text(
                  "view_details".t(context: context),
                  style: context.textTheme.labelLarge?.copyWith(color: context.colorScheme.onSurface.withAlpha(200)),
                ),
                trailing: Icon(
                  context.platformIcons.rightChevron,
                  size: 16,
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _TotalCard extends ConsumerWidget {
  const _TotalCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalCount = ref.watch(driftBackupProvider.select((p) => p.totalCount));

    return BackupInfoCard(
      title: "total".tr(),
      subtitle: "backup_controller_page_total_sub".tr(),
      info: totalCount.toString(),
    );
  }
}

// ignore: unused_element
class _BackupCard extends ConsumerWidget {
  const _BackupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backupCount = ref.watch(driftBackupProvider.select((p) => p.backupCount));
    final syncStatus = ref.watch(syncStatusProvider);

    return BackupInfoCard(
      title: "backup_controller_page_backup".tr(),
      subtitle: "backup_controller_page_backup_sub".tr(),
      info: backupCount.toString(),
      isLoading: syncStatus.isRemoteSyncing,
    );
  }
}

// ignore: unused_element
class _RemainderCard extends ConsumerWidget {
  const _RemainderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remainderCount = ref.watch(driftBackupProvider.select((p) => p.remainderCount));
    final syncStatus = ref.watch(syncStatusProvider);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: context.colorScheme.outlineVariant, width: 1),
      ),
      elevation: 0,
      borderOnForeground: false,
      child: Column(
        children: [
          ListTile(
            minVerticalPadding: 18,
            isThreeLine: true,
            title: Text("backup_controller_page_remainder".t(context: context), style: context.textTheme.titleMedium),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0, right: 18.0),
              child: Text(
                "backup_controller_page_remainder_sub".t(context: context),
                style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceSecondary),
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  children: [
                    Text(
                      remainderCount.toString(),
                      style: context.textTheme.titleLarge?.copyWith(
                        color: context.colorScheme.onSurface.withAlpha(syncStatus.isRemoteSyncing ? 50 : 255),
                      ),
                    ),
                    if (syncStatus.isRemoteSyncing)
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.colorScheme.onSurface.withAlpha(150),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Text(
                  "backup_info_card_assets",
                  style: context.textTheme.labelLarge?.copyWith(
                    color: context.colorScheme.onSurface.withAlpha(syncStatus.isRemoteSyncing ? 50 : 255),
                  ),
                ).tr(),
              ],
            ),
          ),
          const Divider(height: 0),
          const _PreparingStatus(),
          const Divider(height: 0),

          ListTile(
            enableFeedback: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
            ),
            onTap: () => context.pushRoute(const DriftBackupAssetDetailRoute()),
            title: Text(
              "view_details".t(context: context),
              style: context.textTheme.labelLarge?.copyWith(color: context.colorScheme.onSurface.withAlpha(200)),
            ),
            trailing: Icon(context.platformIcons.rightChevron, size: 16, color: context.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PreparingStatus extends ConsumerStatefulWidget {
  const _PreparingStatus();

  @override
  _PreparingStatusState createState() => _PreparingStatusState();
}

class _PreparingStatusState extends ConsumerState {
  Timer? _pollingTimer;

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPollingIfNeeded() {
    if (_pollingTimer != null) return;

    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final currentUser = ref.read(currentUserProvider);
      if (currentUser != null && mounted) {
        await ref.read(driftBackupProvider.notifier).getBackupStatus(currentUser.id);

        // Stop polling if processing count reaches 0
        final updatedProcessingCount = ref.read(driftBackupProvider.select((p) => p.processingCount));
        if (updatedProcessingCount == 0) {
          timer.cancel();
          _pollingTimer = null;
        }
      } else {
        timer.cancel();
        _pollingTimer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final syncStatus = ref.watch(syncStatusProvider);
    final remainderCount = ref.watch(driftBackupProvider.select((p) => p.remainderCount));
    final processingCount = ref.watch(driftBackupProvider.select((p) => p.processingCount));
    final readyForUploadCount = remainderCount - processingCount;

    ref.listen<int>(driftBackupProvider.select((p) => p.processingCount), (previous, next) {
      if (next > 0 && _pollingTimer == null) {
        _startPollingIfNeeded();
      } else if (next == 0 && _pollingTimer != null) {
        _pollingTimer?.cancel();
        _pollingTimer = null;
      }
    });

    if (!syncStatus.isHashing) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 1.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
              decoration: BoxDecoration(
                color: context.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                shape: BoxShape.rectangle,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        "preparing".t(context: context),
                        style: context.textTheme.labelLarge?.copyWith(
                          color: context.colorScheme.onSurface.withAlpha(200),
                        ),
                      ),
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.5)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    processingCount.toString(),
                    style: context.textTheme.titleMedium?.copyWith(
                      color: context.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            decoration: BoxDecoration(color: context.colorScheme.primary.withValues(alpha: 0.1)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "ready_for_upload".t(context: context),
                  style: context.textTheme.labelLarge?.copyWith(color: context.colorScheme.onSurface.withAlpha(200)),
                ),
                const SizedBox(height: 2),
                Text(
                  readyForUploadCount.toString(),
                  style: context.textTheme.titleMedium?.copyWith(
                    color: context.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
