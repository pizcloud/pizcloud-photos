import 'package:auto_route/auto_route.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/cast_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/download_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/favorite_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/motion_photo_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/unfavorite_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_viewer.state.dart';
import 'package:immich_mobile/providers/activity.provider.dart';
import 'package:immich_mobile/providers/cast.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset_viewer/current_asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/current_album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/routes.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';

class ViewerTopAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const ViewerTopAppBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = ref.watch(currentAssetNotifier);
    if (asset == null) {
      return const SizedBox.shrink();
    }

    final album = ref.watch(currentRemoteAlbumProvider);

    final user = ref.watch(currentUserProvider);
    final isOwner = asset is RemoteAsset && asset.ownerId == user?.id;
    final isInLockedView = ref.watch(inLockedViewProvider);
    final isReadonlyModeEnabled = ref.watch(readonlyModeProvider);

    final timelineOrigin = ref.read(timelineServiceProvider).origin;
    final showViewInTimelineButton =
        timelineOrigin != TimelineOrigin.main &&
        timelineOrigin != TimelineOrigin.deepLink &&
        timelineOrigin != TimelineOrigin.trash &&
        timelineOrigin != TimelineOrigin.archive &&
        timelineOrigin != TimelineOrigin.localAlbum &&
        isOwner;

    final isShowingSheet = ref.watch(assetViewerProvider.select((state) => state.showingBottomSheet));
    final barColor = Colors.transparent;
    int opacity = ref.watch(assetViewerProvider.select((state) => state.backgroundOpacity));
    final showControls = ref.watch(assetViewerProvider.select((s) => s.showingControls));

    if (album != null && album.isActivityEnabled && album.isShared && asset is RemoteAsset) {
      ref.watch(albumActivityProvider(album.id, asset.id));
    }

    if (!showControls) {
      opacity = 0;
    }

    final isCasting = ref.watch(castProvider.select((c) => c.isCasting));

    final actions = <Widget>[
      if (asset.isRemoteOnly) const DownloadActionButton(source: ActionSource.viewer, menuItem: true),
      if (isCasting || (asset.hasRemote)) const CastActionButton(menuItem: true),
      if (album != null && album.isActivityEnabled && album.isShared)
        IconButton(
          icon: const Icon(Icons.chat_outlined),
          onPressed: () {
            EventStream.shared.emit(const ViewerOpenBottomSheetEvent(activitiesMode: true));
          },
        ),
      if (showViewInTimelineButton)
        IconButton(
          onPressed: () async {
            await context.maybePop();
            await context.navigateTo(const TabShellRoute(children: [MainTimelineRoute()]));
            EventStream.shared.emit(ScrollToDateEvent(asset.createdAt));
          },
          icon: const Icon(Icons.image_search),
          tooltip: 'view_in_timeline'.t(context: context),
        ),
      if (asset.hasRemote && isOwner && !asset.isFavorite)
        const FavoriteActionButton(source: ActionSource.viewer, menuItem: true),
      if (asset.hasRemote && isOwner && asset.isFavorite)
        const UnFavoriteActionButton(source: ActionSource.viewer, menuItem: true),
      if (asset.isMotionPhoto) const MotionPhotoActionButton(menuItem: true),
      const _KebabMenu(),
    ];

    final lockedViewActions = <Widget>[
      if (isCasting || (asset.hasRemote)) const CastActionButton(menuItem: true),
      const _KebabMenu(),
    ];

    final trailing = isShowingSheet || isReadonlyModeEnabled
        ? null
        : isInLockedView
        ? lockedViewActions
        : actions;

    return IgnorePointer(
      ignoring: opacity < 255,
      child: AnimatedOpacity(
        opacity: opacity / 255,
        duration: Durations.short2,
        child: Theme(
          data: context.themeData.copyWith(
            iconTheme: const IconThemeData(size: 22, color: Colors.white),
            textTheme: context.themeData.textTheme.copyWith(
              labelLarge: context.themeData.textTheme.labelLarge?.copyWith(color: Colors.white),
            ),
          ),
          child: Container(
            height: context.padding.top + 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withAlpha(70), Colors.black.withAlpha(110)],
              ),
            ),
            padding: EdgeInsets.only(top: context.padding.top, left: 4, right: 4),
            child: Align(
              alignment: Alignment.center,
              child: SizedBox(
                height: 44,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const _AppBarBackButton(),
                    const Spacer(),
                    if (trailing != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Row(children: trailing),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(60.0);
}

class _KebabMenu extends ConsumerWidget {
  const _KebabMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      onPressed: () {
        EventStream.shared.emit(const ViewerOpenBottomSheetEvent());
      },
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      icon: Icon(context.platformIcon(material: Icons.more_vert_rounded, cupertino: CupertinoIcons.ellipsis)),
    );
  }
}

class _AppBarBackButton extends ConsumerWidget {
  const _AppBarBackButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isShowingSheet = ref.watch(assetViewerProvider.select((state) => state.showingBottomSheet));
    final backgroundColor = isShowingSheet && !context.isDarkTheme ? Colors.white : Colors.black.withAlpha(90);
    final foregroundColor = isShowingSheet && !context.isDarkTheme ? Colors.black : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: PlatformWidget(
        cupertino: (_, __) => CupertinoButton(
          padding: const EdgeInsets.all(6),
          minimumSize: const Size(32, 32),
          borderRadius: BorderRadius.circular(20),
          color: backgroundColor.withAlpha(120),
          onPressed: context.maybePop,
          child: Icon(context.platformIcons.back, size: 20, color: foregroundColor),
        ),
        material: (_, __) => Material(
          color: backgroundColor,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: context.maybePop,
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: Icon(Icons.arrow_back_rounded, size: 20, color: foregroundColor),
            ),
          ),
        ),
      ),
    );
  }
}
