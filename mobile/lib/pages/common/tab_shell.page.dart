import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/auth.provider.dart'; // pizcloud
import 'package:immich_mobile/providers/haptic_feedback.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/tab.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/providers/pizcloud/album_transfer.provider.dart'; // pizcloud
import 'package:immich_mobile/providers/pizcloud/new_library.provider.dart'; // pizcloud
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/media_permission_service.dart'; // pizcloud
import 'package:immich_mobile/providers/media_permission.provider.dart'; // pizcloud

// pizcloud: new imports
import 'package:immich_mobile/widgets/media_permissions/media_permission_banner.dart';
import 'package:immich_mobile/widgets/media_permissions/media_permission_lifecycle_listener.dart';
// #pizcloud

@RoutePage()
class TabShellPage extends ConsumerStatefulWidget {
  const TabShellPage({super.key});

  @override
  ConsumerState<TabShellPage> createState() => _TabShellPageState();
}

class _TabShellPageState extends ConsumerState<TabShellPage> {
  StreamSubscription? _eventSubscription;
  bool _hideNavigationBar = false;

  @override
  void initState() {
    super.initState();
    _eventSubscription = EventStream.shared.listen<MultiSelectToggleEvent>(_onMultiSelectToggle);
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }

  void _onMultiSelectToggle(MultiSelectToggleEvent event) {
    if (_hideNavigationBar == event.isEnabled) {
      return;
    }

    setState(() {
      _hideNavigationBar = event.isEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isScreenLandscape = context.orientation == Orientation.landscape;
    final isReadonlyModeEnabled = ref.watch(readonlyModeProvider);

    final navigationDestinations = [
      NavigationDestination(
        label: 'library'.tr(),
        icon: Icon(context.platformIcon(material: Icons.grid_view_rounded, cupertino: CupertinoIcons.square_grid_2x2)),
        selectedIcon: Icon(
          context.platformIcon(material: Icons.grid_view_rounded, cupertino: CupertinoIcons.square_grid_2x2_fill),
          color: context.primaryColor,
        ),
      ),
      NavigationDestination(
        label: 'backup'.tr(),
        icon: Icon(context.platformIcons.cloudUploadSolid),
        selectedIcon: Icon(context.platformIcons.cloudUploadSolid, color: context.primaryColor),
        enabled: !isReadonlyModeEnabled,
      ),
      NavigationDestination(
        label: 'collection'.tr(),
        icon: Icon(context.platformIcon(material: Icons.collections, cupertino: CupertinoIcons.collections_solid)),
        selectedIcon: Icon(
          context.platformIcon(material: Icons.collections, cupertino: CupertinoIcons.collections_solid),
          color: context.primaryColor,
        ),
        enabled: !isReadonlyModeEnabled,
      ),
      NavigationDestination(
        label: 'settings'.tr(),
        icon: Icon(context.platformIcon(material: Icons.settings, cupertino: CupertinoIcons.gear_solid)),
        selectedIcon: Icon(
          context.platformIcon(material: Icons.settings, cupertino: CupertinoIcons.gear_solid),
          color: context.primaryColor,
        ),
        enabled: !isReadonlyModeEnabled,
      ),
    ];

    Widget navigationRail(TabsRouter tabsRouter) {
      return NavigationRail(
        destinations: navigationDestinations
            .map(
              (e) => NavigationRailDestination(
                icon: e.icon,
                label: Text(e.label),
                selectedIcon: e.selectedIcon,
                disabled: !e.enabled,
              ),
            )
            .toList(),
        onDestinationSelected: (index) => _onNavigationSelected(tabsRouter, index, ref),
        selectedIndex: tabsRouter.activeIndex,
        labelType: NavigationRailLabelType.all,
        groupAlignment: 0.0,
      );
    }

    return AutoTabsRouter(
      // pizcloud
      routes: const [NewLibraryRoute(), DriftBackupRoute(), DriftAlbumsRoute(), SettingsTabRoute()],
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (context, child, animation) => FadeTransition(opacity: animation, child: child),
      builder: (context, child) {
        final tabsRouter = AutoTabsRouter.of(context);
        // pizcloud
        final showMediaPermissionBanner = ref.watch(
          mediaPermissionProvider.select((s) => s == MediaPermState.none || s == MediaPermState.limited),
        );
        // #pizcloud
        final showBottomBar = !isScreenLandscape && !_hideNavigationBar;
        final bottomItems = navigationDestinations
            .map(
              (destination) => BottomNavigationBarItem(
                icon: destination.icon,
                activeIcon: destination.selectedIcon ?? destination.icon,
                label: destination.label,
              ),
            )
            .toList();
        final bottomBar = showBottomBar
            ? PlatformNavBar(
                items: bottomItems,
                currentIndex: tabsRouter.activeIndex,
                itemChanged: (index) => _onNavigationSelected(tabsRouter, index, ref),
                cupertino: (_, __) => CupertinoTabBarData(
                  height: 65,
                  iconSize: 22,
                  activeColor: context.primaryColor,
                  inactiveColor: context.colorScheme.onSurface.withValues(alpha: 0.6),
                  backgroundColor: context.colorScheme.surface.withValues(alpha: 0.94),
                  border: Border(top: BorderSide(color: context.colorScheme.outline.withValues(alpha: 0.2))),
                ),
                material3: (_, __) => MaterialNavigationBarData(
                  items: navigationDestinations,
                  selectedIndex: tabsRouter.activeIndex,
                  onDestinationSelected: (index) => _onNavigationSelected(tabsRouter, index, ref),
                ),
              )
            : null;

        Widget buildTabContent() {
          final content = showMediaPermissionBanner
              ? MediaQuery.removePadding(context: context, removeTop: true, child: child)
              : child;

          return Column(
            children: [
              if (showMediaPermissionBanner) const MediaPermissionBanner(),
              Expanded(child: content),
              if (isCupertino(context) && bottomBar != null) SafeArea(top: false, child: bottomBar),
            ],
          );
        }

        return PopScope(
          canPop: tabsRouter.activeIndex == 0,
          onPopInvokedWithResult: (didPop, _) => !didPop ? tabsRouter.setActiveIndex(0) : null,
          child: PlatformScaffold(
            material: (_, __) => MaterialScaffoldData(resizeToAvoidBottomInset: false, bottomNavBar: bottomBar),
            body: Stack(
              children: [
                if (isScreenLandscape)
                  Row(
                    children: [
                      navigationRail(tabsRouter),
                      const VerticalDivider(),
                      // pizcloud: Media permission banner + child
                      Expanded(child: buildTabContent()),
                      // #pizcloud
                    ],
                  )
                else
                  buildTabContent(),

                const MediaPermissionLifecycleListener(),
              ],
            ),
          ),
        );
      },
    );
  }
}

// pizcloud
void _onNavigationSelected(TabsRouter router, int index, WidgetRef ref) {
  // Active shell behavior:
  // NewLibrary / Backup / Albums / Settings
  if (index == kAlbumsTabIndex) {
    unawaited(() async {
      await ref.read(remoteAlbumProvider.notifier).refresh();
      final userId = ref.read(authProvider).userId;
      if (userId.isEmpty) {
        return;
      }
      // final albumIds = ownedAlbumIds(albums: ref.read(remoteAlbumProvider).albums, ownerId: userId);
      // for (final albumId in albumIds) {
      //   ref.invalidate(albumTransferByAlbumProvider(albumId));
      // }
      await refreshTransferIndicatorsForWidget(
        ref,
        albums: ref.read(remoteAlbumProvider).albums,
        ownerId: userId,
        reason: TransferRefreshReason.tabEnter,
      );
    }());
  }

  if (router.activeIndex == kNewLibraryTabIndex && index == kNewLibraryTabIndex) {
    ref.read(newLibraryReselectSignalProvider.notifier).state++;
  }

  ref.read(hapticFeedbackProvider.notifier).selectionClick();
  router.setActiveIndex(index);
  ref.read(tabProvider.notifier).state = _tabForShellIndex(index);
}

TabEnum _tabForShellIndex(int index) {
  return switch (index) {
    kNewLibraryTabIndex => TabEnum.newLibrary,
    kBackupTabIndex => TabEnum.backup,
    kAlbumsTabIndex => TabEnum.albums,
    kSettingsTabIndex => TabEnum.settings,
    _ => TabEnum.newLibrary,
  };
}

// #pizcloud
