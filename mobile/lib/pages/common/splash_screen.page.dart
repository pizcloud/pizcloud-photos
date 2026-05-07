import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/utils/background_sync.dart'; // pizcloud
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/backup/drift_backup.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/repositories/resumable_upload.repository.dart'; // pizcloud
import 'package:immich_mobile/routing/router.dart';
import 'package:logging/logging.dart';

@RoutePage()
class SplashScreenPage extends StatefulHookConsumerWidget {
  const SplashScreenPage({super.key});

  @override
  SplashScreenPageState createState() => SplashScreenPageState();
}

class SplashScreenPageState extends ConsumerState<SplashScreenPage> {
  final log = Logger("SplashScreenPage");

  @override
  void initState() {
    super.initState();
    // pizcloud
    // ref
    //     .read(authProvider.notifier)
    //     .setOpenApiServiceEndpoint()
    //     .then(logConnectionInfo)
    //     .whenComplete(() => resumeSession());
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      final endpoint = await ref.read(authProvider.notifier).setOpenApiServiceEndpoint();
      logConnectionInfo(endpoint);
    } finally {
      await resumeSession();
    }
    // #pizcloud
  }

  void logConnectionInfo(String? endpoint) {
    if (endpoint == null) {
      return;
    }

    log.info("Resuming session at $endpoint");
  }

  Future<void> resumeSession() async {
    // pizcloud
    final serverUrl = Store.tryGet(StoreKey.serverUrl);
    final endpoint = Store.tryGet(StoreKey.serverEndpoint);
    final accessToken = Store.tryGet(StoreKey.accessToken);

    // pizcloud
    if (accessToken == null || serverUrl == null || endpoint == null) {
      log.severe('Missing crucial offline login info - Logging out completely');
      await ref.read(authProvider.notifier).logout();
      if (!mounted) {
        return;
      }
      await context.replaceRoute(const LoginRoute());
      return;
    }

    final infoProvider = ref.read(serverInfoProvider.notifier);
    final wsProvider = ref.read(websocketProvider.notifier);
    final backgroundManager = ref.read(backgroundSyncProvider);
    final driftBackupNotifier = ref.read(driftBackupProvider.notifier);
    final legacyBackupNotifier = ref.read(backupProvider.notifier);
    final galleryPermissionNotifierController = ref.read(galleryPermissionNotifier.notifier);

    // Old flow restored auth in the background and navigated away immediately.
    // That allowed the shell to mount before auth bootstrap finished:
    // unawaited(
    //   ref.read(authProvider.notifier).saveAuthInfo(accessToken: accessToken).then(...),
    // );
    bool authSaved = false;
    try {
      authSaved = await ref.read(authProvider.notifier).saveAuthInfo(accessToken: accessToken);
    } catch (error, stackTrace) {
      log.severe('Failed to update auth info from stored session', error, stackTrace);
    }

    if (authSaved != true) {
      log.severe('Failed to restore auth info from stored session');
      await ref.read(authProvider.notifier).logout();
      if (!mounted) {
        return;
      }
      await context.replaceRoute(const LoginRoute());
      return;
    }
    // #pizcloud

    if (context.router.current.name == SplashScreenRoute.name) {
      final needBetaMigration = Store.get(StoreKey.needBetaMigration, false);
      if (needBetaMigration) {
        await Store.put(StoreKey.needBetaMigration, false);
        // pizcloud
        if (!mounted) {
          return;
        }
        await context.router.replaceAll([ChangeExperienceRoute(switchingToBeta: true)]);
        unawaited(
          _runPostRestoreTasks(
            backgroundManager: backgroundManager,
            infoProvider: infoProvider,
            wsProvider: wsProvider,
            driftBackupNotifier: driftBackupNotifier,
          ),
        );
        // #pizcloud
        return;
      }

      if (!mounted) {
        return;
      } // pizcloud
      await context.replaceRoute(
        Store.isBetaTimelineEnabled ? const TabShellRoute() : const TabControllerRoute(),
      ); // pizcloud
    }

    // pizcloud
    unawaited(
      _runPostRestoreTasks(
        backgroundManager: backgroundManager,
        infoProvider: infoProvider,
        wsProvider: wsProvider,
        driftBackupNotifier: driftBackupNotifier,
      ),
    );
    // #pizcloud

    if (Store.isBetaTimelineEnabled) {
      return;
    }

    final hasPermission = galleryPermissionNotifierController.hasPermission; // pizcloud
    if (hasPermission) {
      // Resume backup (if enable) after auth/session restore has completed.
      await legacyBackupNotifier.resumeBackup(); // pizcloud
    }
  }

  // pizcloud
  Future<void> _runPostRestoreTasks({
    required BackgroundSyncManager backgroundManager,
    required ServerInfoNotifier infoProvider,
    required WebsocketNotifier wsProvider,
    required DriftBackupNotifier driftBackupNotifier,
  }) async {
    try {
      wsProvider.connect();
      unawaited(infoProvider.getServerInfo());

      if (!Store.isBetaTimelineEnabled) {
        return;
      }

      final resumableUploadRepository = ref.read(resumableUploadRepositoryProvider); // pizcloud
      bool syncSuccess = false;
      await Future.wait([
        backgroundManager.syncLocal(full: true),
        backgroundManager.syncRemote().then((success) => syncSuccess = success),
      ]);

      await backgroundManager.hashAssets();
      // pizcloud
      final hasInterruptedResumableSessions = resumableUploadRepository.hasPendingSessions();
      if (syncSuccess || hasInterruptedResumableSessions) {
        if (!syncSuccess && hasInterruptedResumableSessions) {
          log.info("Retrying interrupted resumable uploads despite syncRemote failure");
        }
        // #pizcloud
        await _resumeBackup(driftBackupNotifier);
      }

      if (Store.get(StoreKey.syncAlbums, false)) {
        await backgroundManager.syncLinkedAlbum();
      }
    } catch (error, stackTrace) {
      log.severe('Failed establishing connection to the server', error, stackTrace);
    }
  }
  // #pizcloud

  Future<void> _resumeBackup(DriftBackupNotifier notifier) async {
    final isEnableBackup = Store.get(StoreKey.enableBackup, false);

    if (isEnableBackup) {
      final currentUser = Store.tryGet(StoreKey.currentUser);
      if (currentUser != null) {
        unawaited(notifier.handleBackupResume(currentUser.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const PlatformScaffold(
      body: Center(
        child: Image(image: AssetImage('assets/pizcloud-logo.png'), width: 80, filterQuality: FilterQuality.high),
      ),
    );
  }
}
