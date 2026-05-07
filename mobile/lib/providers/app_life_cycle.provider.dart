import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/services/log.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/backup/backup_state.model.dart';
import 'package:immich_mobile/providers/album/album.provider.dart';
import 'package:immich_mobile/providers/app_settings.provider.dart';
import 'package:immich_mobile/providers/asset.provider.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/backup/drift_backup.provider.dart';
import 'package:immich_mobile/providers/backup/ios_background_settings.provider.dart';
import 'package:immich_mobile/providers/backup/manual_upload.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart' as drift_album; // pizcloud
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/providers/memory.provider.dart';
import 'package:immich_mobile/providers/notification_permission.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/tab.provider.dart';
import 'package:immich_mobile/providers/pizcloud/album_transfer.provider.dart'; // pizcloud
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/repositories/resumable_upload.repository.dart'; // pizcloud
import 'package:immich_mobile/services/app_settings.service.dart'; // pizcloud
import 'package:immich_mobile/services/background.service.dart';
import 'package:immich_mobile/services/pizcloud/backup_observability.service.dart'; // pizcloud
import 'package:immich_mobile/services/pizcloud/photos_api_url_refresher.service.dart'; //pizcloud
import 'package:isar/isar.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

enum AppLifeCycleEnum { active, inactive, paused, resumed, detached, hidden }

class AppLifeCycleNotifier extends StateNotifier<AppLifeCycleEnum> {
  final Ref _ref;
  bool _wasPaused = false;
  final PhotosApiUrlRefresher _photosApiUrlRefresher; // pizcloud

  // Add operation coordination
  Completer<void>? _resumeOperation;
  Completer<void>? _pauseOperation;
  Timer? _interruptedUploadRetryTimer; // pizcloud: periodic retry for interrupted resumable uploads
  bool _isInterruptedUploadRetryInFlight = false; // pizcloud: guard to avoid overlapping retries

  final _log = Logger("AppLifeCycleNotifier");

  AppLifeCycleNotifier(this._ref)
    : _photosApiUrlRefresher = PhotosApiUrlRefresher(_ref), // pizcloud
      super(AppLifeCycleEnum.active) {
    // pizcloud: start best-effort interrupted upload retry ticker on cold start.
    try {
      _startInterruptedUploadRetryTicker();
    } catch (error, stackTrace) {
      _log.fine("Failed to start interrupted upload retry ticker on init", error, stackTrace);
    }
  }

  AppLifeCycleEnum getAppState() {
    return state;
  }

  void handleAppResume() async {
    state = AppLifeCycleEnum.resumed;
    _startInterruptedUploadRetryTicker(); // pizcloud: best-effort periodic retry while app is active

    // pizcloud: keep Photos API URL refreshed while the app is active.
    if (_ref.read(authProvider).isAuthenticated) {
      unawaited(_photosApiUrlRefresher.start());
    } else {
      _photosApiUrlRefresher.stop();
    }
    // #pizcloud

    // Prevent overlapping resume operations
    if (_resumeOperation != null && !_resumeOperation!.isCompleted) {
      await _resumeOperation!.future;
      return;
    }

    // Cancel any ongoing pause operation
    if (_pauseOperation != null && !_pauseOperation!.isCompleted) {
      _pauseOperation!.complete();
    }

    _resumeOperation = Completer<void>();

    try {
      await _performResume();
    } catch (e, stackTrace) {
      _log.severe("Error during app resume", e, stackTrace);
    } finally {
      if (!_resumeOperation!.isCompleted) {
        _resumeOperation!.complete();
      }
      _resumeOperation = null;
    }
  }

  Future<void> _performResume() async {
    // pizcloud
    if (!_wasPaused) {
      if (_ref.read(authProvider).isAuthenticated) {
        unawaited(_gatherAndReportAppResumeState());
      }
      return;
    }
    // #pizcloud
    _wasPaused = false;

    final isAuthenticated = _ref.read(authProvider).isAuthenticated;
    final activeTab = _ref.read(tabProvider); // pizcloud

    // Needs to be logged in
    if (isAuthenticated) {
      // switch endpoint if needed
      final endpoint = await _ref.read(authProvider.notifier).setOpenApiServiceEndpoint();
      _log.info("Using server URL: $endpoint");

      if (!Store.isBetaTimelineEnabled) {
        final permission = _ref.watch(galleryPermissionNotifier);
        if (permission.isGranted || permission.isLimited) {
          await _ref.read(backupProvider.notifier).resumeBackup();
          await _ref.read(backgroundServiceProvider).resumeServiceIfEnabled();
        }
      }

      await _ref.read(serverInfoProvider.notifier).getServerVersion();
    }

    if (!Store.isBetaTimelineEnabled) {
      // Legacy non-beta shell kept compile-safe only.
      // Its tabs are mapped onto the active new-flow enum in tab_controller.page.dart.
      switch (activeTab) {
        case TabEnum.newLibrary:
          await _ref.read(assetProvider.notifier).getAllAsset();

        case TabEnum.albums:
          await _ref.read(albumProvider.notifier).refreshRemoteAlbums();

        case TabEnum.backup:
        case TabEnum.settings:
          break;
      }
    } else {
      _ref.read(websocketProvider.notifier).connect();
      await _handleBetaTimelineResume();
    }
    // pizcloud
    if (isAuthenticated && activeTab == TabEnum.albums) {
      if (!_shouldContinueOperation()) {
        return;
      }
      await _safeRun(_ref.read(drift_album.remoteAlbumProvider.notifier).refresh(), "refreshDriftAlbumsOnResume");
      final userId = _ref.read(authProvider).userId;
      if (userId.isEmpty) {
        return;
      }
      // _ref.invalidate(albumIncomingTransfersProvider);
      // final albumIds = ownedAlbumIds(albums: _ref.read(drift_album.remoteAlbumProvider).albums, ownerId: userId);
      // for (final albumId in albumIds) {
      //   _ref.invalidate(albumTransferByAlbumProvider(albumId));
      // }
      await refreshTransferIndicators(
        _ref,
        albums: _ref.read(drift_album.remoteAlbumProvider).albums,
        ownerId: userId,
        reason: TransferRefreshReason.appResume,
      );
    }
    // #pizcloud

    await _ref.read(notificationPermissionProvider.notifier).getNotificationPermission();

    await _ref.read(galleryPermissionNotifier.notifier).getGalleryPermissionStatus();

    if (!Store.isBetaTimelineEnabled) {
      await _ref.read(iOSBackgroundSettingsProvider.notifier).refresh();

      _ref.invalidate(memoryFutureProvider);
    }

    if (isAuthenticated) {
      unawaited(_gatherAndReportAppResumeState());
    } // pizcloud
  }

  // pizcloud
  Future<void> _gatherAndReportAppResumeState() async {
    try {
      final appSettingsService = _ref.read(appSettingsServiceProvider);
      final isBackupEnabled = appSettingsService.getSetting(AppSettingsEnum.enableBackup);

      // Try to gather asset counts from backup state - best effort only
      BackupObservabilityCounts? latestKnownCounts;
      try {
        if (isBackupEnabled) {
          final backupState = _ref.read(backupProvider);

          // Calculate asset counts from backup state
          final totalAssets = backupState.allUniqueAssets.length;
          final uploadedAssets = backupState.allAssetsInDatabase.length;
          final remainderAssets = totalAssets - uploadedAssets;

          // Only send counts if we have meaningful data
          if (totalAssets > 0) {
            latestKnownCounts = BackupObservabilityCounts(
              total: totalAssets,
              remainder: remainderAssets > 0 ? remainderAssets : 0,
              processing: 0,
            );
          }
        }
      } catch (e, stackTrace) {
        _log.fine("Failed to gather asset counts for app resume telemetry", e, stackTrace);
        // Continue without asset counts - telemetry is best-effort
      }

      await BackupObservabilityService.reportAppResume(
        latestKnownCounts: latestKnownCounts,
        backupEnabled: isBackupEnabled,
      );
    } catch (e, stackTrace) {
      _log.fine("Error gathering app resume telemetry state", e, stackTrace);
      // Silently fail - telemetry should never affect app functionality
    }
  }

  void _startInterruptedUploadRetryTicker() {
    _stopInterruptedUploadRetryTicker();
    if (!Store.isBetaTimelineEnabled) {
      return;
    }

    final retryDelay = _resolveInterruptedUploadRetryDelay();
    _interruptedUploadRetryTimer = Timer.periodic(retryDelay, (_) {
      unawaited(_retryInterruptedUploadsIfNeeded(trigger: 'ticker'));
    });

    // Trigger one immediate best-effort retry on app resume instead of waiting for the first tick.
    unawaited(_retryInterruptedUploadsIfNeeded(trigger: 'resume'));
  }

  Duration _resolveInterruptedUploadRetryDelay() {
    final configuredSeconds = _ref.read(appSettingsServiceProvider).getSetting(AppSettingsEnum.backupTriggerDelay);
    final normalizedSeconds = configuredSeconds > 0
        ? configuredSeconds
        : AppSettingsEnum.backupTriggerDelay.defaultValue;
    return Duration(seconds: normalizedSeconds);
  }

  Future<void> _retryInterruptedUploadsIfNeeded({required String trigger}) async {
    if (_isInterruptedUploadRetryInFlight || !Store.isBetaTimelineEnabled) {
      return;
    }

    if (![AppLifeCycleEnum.resumed, AppLifeCycleEnum.active].contains(state)) {
      return;
    }

    final appSettingsService = _ref.read(appSettingsServiceProvider);
    if (!appSettingsService.getSetting(AppSettingsEnum.enableBackup)) {
      return;
    }

    final currentUser = Store.tryGet(StoreKey.currentUser);
    if (currentUser == null) {
      return;
    }

    final backupState = _ref.read(driftBackupProvider);
    if (backupState.isCanceling) {
      return;
    }

    final resumableUploadRepository = _ref.read(resumableUploadRepositoryProvider);
    final pendingSessionCount = resumableUploadRepository.pendingSessionCount();
    if (pendingSessionCount <= 0) {
      return;
    }

    _isInterruptedUploadRetryInFlight = true;
    try {
      _log.fine("Auto-retrying $pendingSessionCount interrupted upload session(s) from $trigger");
      await _ref.read(driftBackupProvider.notifier).handleBackupResume(currentUser.id);
    } catch (error, stackTrace) {
      _log.warning("Failed auto-retrying interrupted uploads from $trigger", error, stackTrace);
    } finally {
      _isInterruptedUploadRetryInFlight = false;
    }
  }

  void _stopInterruptedUploadRetryTicker() {
    _interruptedUploadRetryTimer?.cancel();
    _interruptedUploadRetryTimer = null;
  }
  // #pizcloud

  Future<void> _safeRun(Future<void> action, String debugName) async {
    if (!_shouldContinueOperation()) {
      return;
    }

    try {
      await action;
    } catch (e, stackTrace) {
      _log.warning("Error during $debugName operation", e, stackTrace);
    }
  }

  Future<void> _handleBetaTimelineResume() async {
    _ref.read(backupProvider.notifier).cancelBackup();
    unawaited(_ref.read(backgroundWorkerLockServiceProvider).lock());

    // Give isolates time to complete any ongoing database transactions
    await Future.delayed(const Duration(milliseconds: 500));

    final backgroundManager = _ref.read(backgroundSyncProvider);
    final isAlbumLinkedSyncEnable = _ref.read(appSettingsServiceProvider).getSetting(AppSettingsEnum.syncAlbums);

    try {
      bool syncSuccess = false;
      await Future.wait([
        _safeRun(backgroundManager.syncLocal(), "syncLocal"),
        _safeRun(backgroundManager.syncRemote().then((success) => syncSuccess = success), "syncRemote"),
      ]);
      if (syncSuccess) {
        // pizcloud
        // await Future.wait([
        //   _safeRun(backgroundManager.hashAssets(), "hashAssets").then((_) {
        //     _resumeBackup();
        //   }),
        //   _resumeBackup(),
        // ]);
        //
        // New behavior:
        // 1) Start resume early (in parallel with hashing) to keep UI responsive.
        // 2) Await hashing completion.
        // 3) Await the early resume call.
        // 4) Re-check resume once after hash, to pick up any newly-hashed candidates.
        final earlyResume = _resumeBackup();
        await _safeRun(backgroundManager.hashAssets(), "hashAssets");
        await earlyResume;
        await _resumeBackup();
        // #pizcloud
      } else {
        await _safeRun(backgroundManager.hashAssets(), "hashAssets");
      }

      if (isAlbumLinkedSyncEnable) {
        await _safeRun(backgroundManager.syncLinkedAlbum(), "syncLinkedAlbum");
      }
    } catch (e, stackTrace) {
      _log.severe("Error during background sync", e, stackTrace);
    }
  }

  Future<void> _resumeBackup() async {
    final isEnableBackup = _ref.read(appSettingsServiceProvider).getSetting(AppSettingsEnum.enableBackup);

    if (isEnableBackup) {
      final currentUser = Store.tryGet(StoreKey.currentUser);
      if (currentUser != null) {
        await _safeRun(
          _ref.read(driftBackupProvider.notifier).handleBackupResume(currentUser.id),
          "handleBackupResume",
        );
      }
    }
  }

  // Helper method to check if operations should continue
  bool _shouldContinueOperation() {
    return [AppLifeCycleEnum.resumed, AppLifeCycleEnum.active].contains(state) &&
        (_resumeOperation?.isCompleted == false || _resumeOperation == null);
  }

  void handleAppInactivity() {
    state = AppLifeCycleEnum.inactive;
    // do not stop/clean up anything on inactivity: issued on every orientation change
  }

  Future<void> handleAppPause() async {
    state = AppLifeCycleEnum.paused;
    _wasPaused = true;
    _photosApiUrlRefresher.stop(); // pizcloud: stop periodic refresh when app is backgrounded.
    _stopInterruptedUploadRetryTicker(); // pizcloud: stop retry ticker while app is not active

    // Prevent overlapping pause operations
    if (_pauseOperation != null && !_pauseOperation!.isCompleted) {
      await _pauseOperation!.future;
      return;
    }

    // Cancel any ongoing resume operation
    if (_resumeOperation != null && !_resumeOperation!.isCompleted) {
      _resumeOperation!.complete();
    }

    _pauseOperation = Completer<void>();

    try {
      if (Store.isBetaTimelineEnabled) {
        unawaited(_ref.read(backgroundWorkerLockServiceProvider).unlock());
      }
      await _performPause();
    } catch (e, stackTrace) {
      _log.severe("Error during app pause", e, stackTrace);
    } finally {
      if (!_pauseOperation!.isCompleted) {
        _pauseOperation!.complete();
      }
      _pauseOperation = null;
    }
  }

  Future<void> _performPause() async {
    if (_ref.read(authProvider).isAuthenticated) {
      if (!Store.isBetaTimelineEnabled) {
        // Do not cancel backup if manual upload is in progress
        if (_ref.read(backupProvider.notifier).backupProgress != BackUpProgressEnum.manualInProgress) {
          _ref.read(backupProvider.notifier).cancelBackup();
        }
      }

      _ref.read(websocketProvider.notifier).disconnect();
    }

    try {
      await LogService.I.flush();
    } catch (_) {}
  }

  Future<void> handleAppDetached() async {
    state = AppLifeCycleEnum.detached;
    _photosApiUrlRefresher.stop(); // pizcloud: stop periodic refresh when app is detached.
    _stopInterruptedUploadRetryTicker(); // pizcloud: stop retry ticker while app is detached

    if (Store.isBetaTimelineEnabled) {
      unawaited(_ref.read(backgroundWorkerLockServiceProvider).unlock());
    }

    // Flush logs before closing database
    try {
      await LogService.I.flush();
    } catch (_) {}

    // Close Isar database safely
    try {
      final isar = Isar.getInstance();
      if (isar != null && isar.isOpen) {
        await isar.close();
      }
    } catch (_) {}

    if (Store.isBetaTimelineEnabled) {
      return;
    }

    // no guarantee this is called at all
    try {
      _ref.read(manualUploadProvider.notifier).cancelBackup();
    } catch (_) {}
  }

  void handleAppHidden() {
    state = AppLifeCycleEnum.hidden;
    _stopInterruptedUploadRetryTicker(); // pizcloud: stop retry ticker while app is hidden
    // do not stop/clean up anything on inactivity: issued on every orientation change
  }

  // pizcloud
  @override
  void dispose() {
    _stopInterruptedUploadRetryTicker(); // pizcloud
    _photosApiUrlRefresher.stop();
    super.dispose();
  }

  // #pizcloud
}

final appStateProvider = StateNotifierProvider<AppLifeCycleNotifier, AppLifeCycleEnum>((ref) {
  return AppLifeCycleNotifier(ref);
});
