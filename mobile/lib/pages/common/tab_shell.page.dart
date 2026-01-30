import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/pages/search/paginated_search.provider.dart';
import 'package:immich_mobile/providers/haptic_feedback.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/memory.provider.dart';
import 'package:immich_mobile/providers/infrastructure/people.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/search/search_input_focus.provider.dart';
import 'package:immich_mobile/providers/tab.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
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
        label: 'photos'.tr(),
        icon: const Icon(Icons.photo_library_outlined),
        selectedIcon: Icon(Icons.photo_library, color: context.primaryColor),
      ),
      NavigationDestination(
        label: 'search'.tr(),
        icon: const Icon(Icons.search_rounded),
        selectedIcon: Icon(Icons.search, color: context.primaryColor),
        enabled: !isReadonlyModeEnabled,
      ),
      NavigationDestination(
        label: 'albums'.tr(),
        icon: const Icon(Icons.photo_album_outlined),
        selectedIcon: Icon(Icons.photo_album_rounded, color: context.primaryColor),
        enabled: !isReadonlyModeEnabled,
      ),
      NavigationDestination(
        label: 'library'.tr(),
        icon: const Icon(Icons.space_dashboard_outlined),
        selectedIcon: Icon(Icons.space_dashboard_rounded, color: context.primaryColor),
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
      routes: const [MainTimelineRoute(), DriftSearchRoute(), DriftAlbumsRoute(), DriftLibraryRoute()],
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
                cupertino: (_, __) => CupertinoTabBarData(height: 65),
                material3: (_, __) => MaterialNavigationBarData(
                  items: navigationDestinations,
                  selectedIndex: tabsRouter.activeIndex,
                  onDestinationSelected: (index) => _onNavigationSelected(tabsRouter, index, ref),
                ),
              )
            : null;

        Widget buildTabContent() {
          return Column(
            children: [
              if (showMediaPermissionBanner) const MediaPermissionBanner(),
              Expanded(child: child),
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

void _onNavigationSelected(TabsRouter router, int index, WidgetRef ref) {
  // On Photos page menu tapped
  if (router.activeIndex == kPhotoTabIndex && index == kPhotoTabIndex) {
    EventStream.shared.emit(const ScrollToTopEvent());
  }

  if (index == kPhotoTabIndex) {
    ref.invalidate(driftMemoryFutureProvider);
  }

  if (router.activeIndex != kSearchTabIndex && index == kSearchTabIndex) {
    ref.read(searchPreFilterProvider.notifier).clear();
  }

  // On Search page tapped
  if (router.activeIndex == kSearchTabIndex && index == kSearchTabIndex) {
    ref.read(searchInputFocusProvider).requestFocus();
  }

  // Album page
  if (index == kAlbumTabIndex) {
    ref.read(remoteAlbumProvider.notifier).refresh();
  }

  // Library page
  if (index == kLibraryTabIndex) {
    ref.invalidate(localAlbumProvider);
    ref.invalidate(driftGetAllPeopleProvider);
  }

  ref.read(hapticFeedbackProvider.notifier).selectionClick();
  router.setActiveIndex(index);
  ref.read(tabProvider.notifier).state = TabEnum.values[index];
}
