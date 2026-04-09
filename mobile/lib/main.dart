import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/constants/locales.dart';
import 'package:immich_mobile/domain/services/background_worker.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/generated/codegen_loader.g.dart';
import 'package:immich_mobile/generated/intl_keys.g.dart';
import 'package:immich_mobile/platform/background_worker_lock_api.g.dart';
import 'package:immich_mobile/providers/app_life_cycle.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/share_intent_upload.provider.dart';
import 'package:immich_mobile/providers/auth.provider.dart'; // pizcloud
import 'package:immich_mobile/providers/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/providers/locale_provider.dart';
import 'package:immich_mobile/providers/routes.provider.dart';
import 'package:immich_mobile/providers/theme.provider.dart';
import 'package:immich_mobile/routing/app_navigation_observer.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/background.service.dart';
import 'package:immich_mobile/services/deep_link.service.dart';
import 'package:immich_mobile/services/local_notification.service.dart';
import 'package:immich_mobile/services/pizcloud/push_notification.service.dart'; // pizcloud
import 'package:immich_mobile/theme/dynamic_theme.dart';
import 'package:immich_mobile/theme/theme_data.dart';
import 'package:immich_mobile/utils/bootstrap.dart';
import 'package:immich_mobile/utils/cache/widgets_binding.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:immich_mobile/utils/http_ssl_options.dart';
import 'package:immich_mobile/utils/licenses.dart';
import 'package:immich_mobile/utils/migration.dart';
import 'package:immich_mobile/wm_executor.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:timezone/data/latest.dart';

void main() async {
  ImmichWidgetsBinding();
  unawaited(BackgroundWorkerLockService(BackgroundWorkerLockApi()).lock());
  final (isar, drift, logDb) = await Bootstrap.initDB();
  await Bootstrap.initDomain(isar, drift, logDb);
  await initApp();
  // Warm-up isolate pool for worker manager
  await workerManagerPatch.init(dynamicSpawning: true, isolatesCount: max(Platform.numberOfProcessors - 1, 5));
  await migrateDatabaseIfNeeded(isar, drift);
  HttpSSLOptions.apply();

  runApp(
    ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(isar),
        isarProvider.overrideWithValue(isar),
        driftProvider.overrideWith(driftOverride(drift)),
      ],
      child: const MainWidget(),
    ),
  );
}

Future<void> initApp() async {
  await EasyLocalization.ensureInitialized();
  await initializeDateFormatting();

  if (kReleaseMode && Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
      dPrint(() => "Enabled high refresh mode");
    } catch (e) {
      dPrint(() => "Error setting high refresh rate: $e");
    }
  }

  await DynamicTheme.fetchSystemPalette();

  final log = Logger("PizCloudErrorLogger");

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    log.severe(
      'FlutterError - Catch all',
      "${details.toString()}\nException: ${details.exception}\nLibrary: ${details.library}\nContext: ${details.context}",
      details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    log.severe('PlatformDispatcher - Catch all', error, stack);
    return true;
  };

  initializeTimeZones();

  // Initialize the file downloader
  await FileDownloader().configure(
    // maxConcurrent: 6, maxConcurrentByHost(server):6, maxConcurrentByGroup: 3

    // On Android, if files are larger than 256MB, run in foreground service
    globalConfig: [(Config.holdingQueue, (6, 6, 3)), (Config.runInForegroundIfFileLargerThan, 256)],
  );

  await FileDownloader().trackTasksInGroup(kDownloadGroupLivePhoto, markDownloadedComplete: false);

  await FileDownloader().trackTasks();

  LicenseRegistry.addLicense(() async* {
    for (final license in nonPubLicenses.entries) {
      yield LicenseEntryWithLineBreaks([license.key], license.value);
    }
  });
}

class ImmichApp extends ConsumerStatefulWidget {
  const ImmichApp({super.key});

  @override
  ImmichAppState createState() => ImmichAppState();
}

class ImmichAppState extends ConsumerState<ImmichApp> with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        dPrint(() => "[APP STATE] resumed");
        ref.read(appStateProvider.notifier).handleAppResume();
        break;
      case AppLifecycleState.inactive:
        dPrint(() => "[APP STATE] inactive");
        ref.read(appStateProvider.notifier).handleAppInactivity();
        break;
      case AppLifecycleState.paused:
        dPrint(() => "[APP STATE] paused");
        ref.read(appStateProvider.notifier).handleAppPause();
        break;
      case AppLifecycleState.detached:
        dPrint(() => "[APP STATE] detached");
        ref.read(appStateProvider.notifier).handleAppDetached();
        break;
      case AppLifecycleState.hidden:
        dPrint(() => "[APP STATE] hidden");
        ref.read(appStateProvider.notifier).handleAppHidden();
        break;
    }
  }

  Future<void> initApp() async {
    WidgetsBinding.instance.addObserver(this);

    // Draw the app from edge to edge
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

    // Sets the navigation bar color
    SystemUiOverlayStyle overlayStyle = const SystemUiOverlayStyle(systemNavigationBarColor: Colors.transparent);
    if (Platform.isAndroid) {
      // Android 8 does not support transparent app bars
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt <= 26) {
        overlayStyle = context.isDarkTheme ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light;
      }
    }
    SystemChrome.setSystemUIOverlayStyle(overlayStyle);
    await ref.read(localNotificationService).setup();
  }

  // pizcloud
  Future<void> _handlePushNotificationTap(Map<String, dynamic> data) async {
    final type = (data['type'] ?? '').toString().trim().toLowerCase();

    if (!ref.read(authProvider).isAuthenticated) {
      return;
    }

    if (type == 'album_transfer_ownership') {
      await _openAlbumsFromPush();
      return;
    }

    if (type != 'album_invite') {
      return;
    }

    final albumId = _extractAlbumIdFromNotification(data);
    if (albumId == null || albumId.isEmpty) {
      return;
    }

    await _openAlbumFromPush(albumId);
  }

  String? _extractAlbumIdFromNotification(Map<String, dynamic> data) {
    final rawAlbumId = data['album_id'] ?? data['albumId'];
    if (rawAlbumId == null) {
      return null;
    }

    final albumId = rawAlbumId.toString().trim();
    if (albumId.isEmpty) {
      return null;
    }

    return albumId;
  }

  Future<void> _openAlbumFromPush(String albumId) async {
    final deepLinkHandler = ref.read(deepLinkServiceProvider);
    final route = await deepLinkHandler.buildAlbumRouteFromNotification(albumId);
    if (route == null || !mounted) {
      return;
    }

    // Old behavior: push notifications did not trigger in-app route navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      unawaited(ref.read(appRouterProvider).push(route));
    });
  }

  Future<void> _openAlbumsFromPush() async {
    if (!mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final appRouter = ref.read(appRouterProvider);
      if (Store.isBetaTimelineEnabled) {
        unawaited(appRouter.navigate(const TabShellRoute(children: [DriftAlbumsRoute()])));
      } else {
        unawaited(appRouter.navigate(const TabControllerRoute(children: [AlbumsRoute()])));
      }
    });
  }
  // #pizcloud

  Future<DeepLink> _deepLinkBuilder(PlatformDeepLink deepLink) async {
    final deepLinkHandler = ref.read(deepLinkServiceProvider);
    final currentRouteName = ref.read(currentRouteNameProvider.notifier).state;

    final isColdStart = currentRouteName == null || currentRouteName == SplashScreenRoute.name;

    if (deepLink.uri.scheme == "immich") {
      final proposedRoute = await deepLinkHandler.handleScheme(deepLink, ref, isColdStart);

      return proposedRoute;
    }

    if (deepLink.uri.host == "photos.pizcloud.com") {
      final proposedRoute = await deepLinkHandler.handleMyImmichApp(deepLink, ref, isColdStart);

      return proposedRoute;
    }

    return DeepLink.path(deepLink.path);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Intl.defaultLocale = context.locale.toLanguageTag();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      configureFileDownloaderNotifications();
    });
  }

  @override
  initState() {
    super.initState();
    PushNotificationService.setTapHandler(_handlePushNotificationTap); // pizcloud
    initApp().then((_) => dPrint(() => "App Init Completed"));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // needs to be delayed so that EasyLocalization is working
      if (Store.isBetaTimelineEnabled) {
        ref.read(backgroundServiceProvider).disableService();
        ref.read(backgroundWorkerFgServiceProvider).enable();
        if (Platform.isAndroid) {
          ref
              .read(backgroundWorkerFgServiceProvider)
              .saveNotificationMessage(
                IntlKeys.uploading_media.t(),
                IntlKeys.backup_background_service_default_notification.t(),
              );
        }
      } else {
        ref.read(backgroundWorkerFgServiceProvider).disable();
        ref.read(backgroundServiceProvider).resumeServiceIfEnabled();
      }
    });

    ref.read(shareIntentUploadProvider.notifier).init();
  }

  @override
  void dispose() {
    PushNotificationService.setTapHandler(null); // pizcloud
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final immichTheme = ref.watch(immichThemeProvider);

    return ProviderScope(
      overrides: [localeProvider.overrideWithValue(context.locale)],
      child: PlatformProvider(
        settings: PlatformSettingsData(
          // Allow existing Material widgets while we migrate UI in phase 2.
          iosUsesMaterialWidgets: true,
        ),
        builder: (context) {
          final themeMode = ref.watch(immichThemeModeProvider);
          final lightTheme = getThemeData(colorScheme: immichTheme.light, locale: context.locale);
          final darkTheme = getThemeData(colorScheme: immichTheme.dark, locale: context.locale);
          final cupertinoLightTheme = getCupertinoThemeData(colorScheme: immichTheme.light, locale: context.locale);
          final cupertinoDarkTheme = getCupertinoThemeData(colorScheme: immichTheme.dark, locale: context.locale);

          return PlatformTheme(
            themeMode: themeMode,
            materialLightTheme: lightTheme,
            materialDarkTheme: darkTheme,
            cupertinoLightTheme: cupertinoLightTheme,
            cupertinoDarkTheme: cupertinoDarkTheme,
            builder: (context) {
              final platformTheme = PlatformTheme.of(context);
              final isDark = platformTheme?.isDark ?? Theme.of(context).brightness == Brightness.dark;
              final cupertinoTheme = isDark ? cupertinoDarkTheme : cupertinoLightTheme;

              // Old MaterialApp.router (kept for comparison)
              // MaterialApp.router(
              //   title: 'PizCloud',
              //   debugShowCheckedModeBanner: true,
              //   localizationsDelegates: context.localizationDelegates,
              //   supportedLocales: context.supportedLocales,
              //   locale: context.locale,
              //   themeMode: themeMode,
              //   darkTheme: darkTheme,
              //   theme: lightTheme,
              //   routerConfig: router.config(
              //     deepLinkBuilder: _deepLinkBuilder,
              //     navigatorObservers: () => [AppNavigationObserver(ref: ref)],
              //   ),
              // );

              return PlatformApp.router(
                title: 'PizCloud',
                debugShowCheckedModeBanner: true,
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                routerConfig: router.config(
                  deepLinkBuilder: _deepLinkBuilder,
                  navigatorObservers: () => [AppNavigationObserver(ref: ref)],
                ),
                material: (_, __) => MaterialAppRouterData(
                  themeMode: themeMode,
                  theme: lightTheme,
                  darkTheme: darkTheme,
                  debugShowCheckedModeBanner: true,
                ),
                cupertino: (_, __) => CupertinoAppRouterData(theme: cupertinoTheme, debugShowCheckedModeBanner: true),
              );
            },
          );
        },
      ),
    );
  }
}

class MainWidget extends StatelessWidget {
  const MainWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      supportedLocales: locales.values.toList(),
      path: translationsPath,
      useFallbackTranslations: true,
      fallbackLocale: locales.values.first,
      assetLoader: const CodegenLoader(),
      child: const ImmichApp(),
    );
  }
}
