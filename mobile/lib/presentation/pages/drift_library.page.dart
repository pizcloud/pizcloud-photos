import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/extensions/asyncvalue_extensions.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/images/local_album_thumbnail.widget.dart';
import 'package:immich_mobile/presentation/widgets/people/partner_user_avatar.widget.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/partner.provider.dart';
import 'package:immich_mobile/providers/infrastructure/people.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';
import 'package:immich_mobile/widgets/map/map_thumbnail.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

@RoutePage()
class DriftLibraryPage extends ConsumerWidget {
  const DriftLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Previous layout with ImmichSliverAppBar (kept for reference)
    // return const PlatformScaffold(
    //   body: CustomScrollView(
    //     slivers: [
    //       ImmichSliverAppBar(snap: false, floating: false, pinned: true, showUploadButton: false),
    //       _ActionButtonGrid(),
    //       _CollectionCards(),
    //       _QuickAccessButtonList(),
    //     ],
    //   ),
    // );
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text('library'.t(context: context)),
        leading: IconButton(
          onPressed: () => context.maybePop(),
          icon: Icon(context.platformIcons.back),
          splashRadius: 24,
        ),
        material: (_, __) => MaterialAppBarData(centerTitle: false),
      ),
      // pizcloud
      // Legacy body
      // body: const CustomScrollView(
      //   slivers: [
      //     _ActionButtonGrid(),
      //     _CollectionCards(),
      //     _QuickAccessButtonList(),
      //   ],
      // ),
      body: const CustomScrollView(
        slivers: [
          _LibraryIntroHeader(),
          _LibraryQuickActionsSection(),
          _LibraryExploreSection(),
          _LibraryManageSection(),
        ],
      ),
      // #pizcloud
    );
  }
}

// pizcloud
class _LibraryIntroHeader extends ConsumerWidget {
  const _LibraryIntroHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peopleAsync = ref.watch(driftGetAllPeopleProvider);
    final albumsAsync = ref.watch(localAlbumProvider);
    final partnersAsync = ref.watch(driftSharedWithPartnerProvider);

    final peopleCount = peopleAsync.valueOrNull?.length;
    final albumsCount = albumsAsync.valueOrNull?.length;
    final partnersCount = partnersAsync.valueOrNull?.length;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      sliver: SliverToBoxAdapter(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(24)),
            gradient: LinearGradient(
              colors: [context.colorScheme.primary.withAlpha(26), context.colorScheme.primary.withAlpha(14)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: context.colorScheme.primary.withAlpha(28)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'library_header_title'.t(context: context),
                  style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                // const SizedBox(height: 4),
                // Text(
                //   'library_header_subtitle'.t(context: context),
                //   style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurface.withAlpha(160)),
                // ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _LibraryStatChip(
                      icon: Icons.face_outlined,
                      label: 'people'.t(context: context),
                      value: peopleCount,
                    ),
                    _LibraryStatChip(
                      icon: Icons.photo_library_outlined,
                      label: 'on_this_device'.t(context: context),
                      value: albumsCount,
                    ),
                    _LibraryStatChip(
                      icon: Icons.group_outlined,
                      label: 'partners'.t(context: context),
                      value: partnersCount,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryStatChip extends StatelessWidget {
  const _LibraryStatChip({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.colorScheme.surface.withAlpha(175),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(color: context.colorScheme.outline.withAlpha(28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: context.primaryColor),
          const SizedBox(width: 6),
          Text('${value ?? '-'} · $label', style: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _LibraryQuickActionsSection extends ConsumerWidget {
  const _LibraryQuickActionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTrashEnable = ref.watch(serverInfoProvider.select((state) => state.serverFeatures.trash));

    final actions = <_LibraryQuickActionItem>[
      _LibraryQuickActionItem(
        icon: Icons.favorite_outline_rounded,
        title: 'favorites'.t(context: context),
        subtitle: 'library_action_favorites_subtitle'.t(context: context),
        onTap: () => context.pushRoute(const DriftFavoriteRoute()),
      ),
      _LibraryQuickActionItem(
        icon: Icons.archive_outlined,
        title: 'archived'.t(context: context),
        subtitle: 'library_action_archive_subtitle'.t(context: context),
        onTap: () => context.pushRoute(const DriftArchiveRoute()),
      ),
      _LibraryQuickActionItem(
        icon: Icons.link_outlined,
        title: 'shared_links'.t(context: context),
        subtitle: 'library_action_shared_subtitle'.t(context: context),
        onTap: () => context.pushRoute(const SharedLinkRoute()),
      ),
      if (isTrashEnable)
        _LibraryQuickActionItem(
          icon: Icons.delete_outline_rounded,
          title: 'trash'.t(context: context),
          subtitle: 'library_action_trash_subtitle'.t(context: context),
          onTap: () => context.pushRoute(const DriftTrashRoute()),
        ),
    ];

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _LibrarySectionHeader(
              title: 'library_quick_actions_title',
              subtitle: 'library_quick_actions_subtitle',
              icon: Icons.bolt_outlined,
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final isTablet = constraints.maxWidth > 700;
                final columns = isTablet ? 4 : 2;
                final tileSpacing = 8.0;
                final tileWidth = (constraints.maxWidth - (columns - 1) * tileSpacing) / columns;
                return Wrap(
                  spacing: tileSpacing,
                  runSpacing: tileSpacing,
                  children: actions
                      .map(
                        (item) => SizedBox(
                          width: tileWidth,
                          child: _LibraryQuickActionCard(item: item),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryQuickActionItem {
  const _LibraryQuickActionItem({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _LibraryQuickActionCard extends StatelessWidget {
  const _LibraryQuickActionCard({required this.item});

  final _LibraryQuickActionItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      onTap: item.onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          color: context.colorScheme.surfaceContainerLow,
          border: Border.all(color: context.colorScheme.outline.withAlpha(28)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  color: context.colorScheme.primary.withAlpha(24),
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                ),
                child: Icon(item.icon, color: context.primaryColor, size: 20),
              ),
              const SizedBox(height: 12),
              Text(item.title, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(150)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryExploreSection extends StatelessWidget {
  const _LibraryExploreSection();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _LibrarySectionHeader(
              title: 'library_explore_title',
              subtitle: 'library_explore_subtitle',
              icon: Icons.explore_outlined,
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final isTablet = constraints.maxWidth > 700;
                if (isTablet) {
                  return const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _LibraryExplorePeopleCard()),
                      SizedBox(width: 10),
                      Expanded(child: _LibraryExplorePlacesCard()),
                      SizedBox(width: 10),
                      Expanded(child: _LibraryExploreLocalAlbumsCard()),
                    ],
                  );
                }

                return const Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _LibraryExplorePeopleCard()),
                        SizedBox(width: 10),
                        Expanded(child: _LibraryExplorePlacesCard()),
                      ],
                    ),
                    SizedBox(height: 10),
                    _LibraryExploreLocalAlbumsCard(),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryExploreCardShell extends StatelessWidget {
  const _LibraryExploreCardShell({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          border: Border.all(color: context.colorScheme.outline.withAlpha(24)),
          gradient: LinearGradient(
            colors: [context.colorScheme.primary.withAlpha(20), context.colorScheme.primary.withAlpha(10)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 140, child: child),
              const SizedBox(height: 10),
              Text(title, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(150)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryExplorePeopleCard extends ConsumerWidget {
  const _LibraryExplorePeopleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peopleAsync = ref.watch(driftGetAllPeopleProvider);

    return _LibraryExploreCardShell(
      title: 'people'.t(context: context),
      subtitle: 'library_explore_people_subtitle'.t(context: context),
      onTap: () => context.pushRoute(const DriftPeopleCollectionRoute()),
      child: peopleAsync.widgetWhen(
        onLoading: () => const _CardSkeleton(),
        onData: (people) {
          if (people.isEmpty) {
            return _CardEmptyState(
              icon: Icons.face_rounded,
              text: 'library_empty_people'.t(context: context),
            );
          }

          return GridView.count(
            crossAxisCount: 2,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: people.take(4).map((person) {
              return CircleAvatar(
                backgroundImage: NetworkImage(getFaceThumbnailUrl(person.id), headers: ApiService.getRequestHeaders()),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _LibraryExplorePlacesCard extends StatelessWidget {
  const _LibraryExplorePlacesCard();

  @override
  Widget build(BuildContext context) {
    return _LibraryExploreCardShell(
      title: 'places'.t(context: context),
      subtitle: 'library_explore_places_subtitle'.t(context: context),
      onTap: () => context.pushRoute(DriftPlaceRoute(currentLocation: null)),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: IgnorePointer(
          child: MapThumbnail(
            zoom: 8,
            centre: const LatLng(21.44950, -157.91959),
            showAttribution: false,
            themeMode: context.isDarkTheme ? ThemeMode.dark : ThemeMode.light,
          ),
        ),
      ),
    );
  }
}

class _LibraryExploreLocalAlbumsCard extends ConsumerWidget {
  const _LibraryExploreLocalAlbumsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumsAsync = ref.watch(localAlbumProvider);

    return _LibraryExploreCardShell(
      title: 'on_this_device'.t(context: context),
      subtitle: 'library_explore_local_albums_subtitle'.t(context: context),
      onTap: () => context.pushRoute(const DriftLocalAlbumsRoute()),
      child: albumsAsync.when(
        data: (data) {
          if (data.isEmpty) {
            return _CardEmptyState(
              icon: Icons.photo_library_outlined,
              text: 'library_empty_local_albums'.t(context: context),
            );
          }

          final previewAlbumIds = data.take(4).map((album) => album.id).toList();
          return _LibraryLocalAlbumsPreviewCollage(albumIds: previewAlbumIds);
        },
        error: (_, __) => _CardEmptyState(
          icon: Icons.error_outline,
          text: 'library_error_local_albums'.t(context: context),
        ),
        loading: () => const _CardSkeleton(),
      ),
    );
  }
}

class _LibraryLocalAlbumsPreviewCollage extends StatelessWidget {
  const _LibraryLocalAlbumsPreviewCollage({required this.albumIds});

  final List<String> albumIds;

  @override
  Widget build(BuildContext context) {
    if (albumIds.isEmpty) {
      return const SizedBox.shrink();
    }

    final overlayIds = albumIds.skip(1).take(3).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final overlaySize = (constraints.maxHeight * 0.34).clamp(38.0, 52.0);

        return ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: LocalAlbumThumbnail(albumId: albumIds.first)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withAlpha(70)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              if (overlayIds.isNotEmpty)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: List.generate(overlayIds.length, (index) {
                      final albumId = overlayIds[index];
                      return Padding(
                        padding: EdgeInsets.only(left: index == 0 ? 0 : 6),
                        child: Container(
                          width: overlaySize,
                          height: overlaySize,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.all(Radius.circular(10)),
                            border: Border.all(color: Colors.white.withAlpha(170), width: 1.1),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withAlpha(36), blurRadius: 8, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.all(Radius.circular(10)),
                            child: LocalAlbumThumbnail(albumId: albumId),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LibraryManageSection extends ConsumerWidget {
  const _LibraryManageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerSharedWithAsync = ref.watch(driftSharedWithPartnerProvider);
    final partners = partnerSharedWithAsync.valueOrNull ?? [];

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _LibrarySectionHeader(
              title: 'library_manage_title',
              subtitle: 'library_manage_subtitle',
              icon: Icons.verified_user_outlined,
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: context.colorScheme.outline.withAlpha(24)),
                borderRadius: const BorderRadius.all(Radius.circular(20)),
                color: context.colorScheme.surfaceContainerLow.withAlpha(150),
              ),
              child: Column(
                children: [
                  _LibraryManageTile(
                    icon: Icons.folder_outlined,
                    title: 'folders'.t(context: context),
                    subtitle: 'library_manage_folders_subtitle'.t(context: context),
                    onTap: () => context.pushRoute(FolderRoute()),
                  ),
                  _LibraryManageTile(
                    icon: Icons.lock_outline_rounded,
                    title: 'locked_folder'.t(context: context),
                    subtitle: 'library_manage_locked_subtitle'.t(context: context),
                    onTap: () => context.pushRoute(const DriftLockedFolderRoute()),
                  ),
                  _LibraryManageTile(
                    icon: Icons.group_outlined,
                    title: 'partners'.t(context: context),
                    subtitle: 'library_manage_partners_subtitle'.t(context: context),
                    onTap: () => context.pushRoute(const DriftPartnerRoute()),
                  ),
                  if (partners.isNotEmpty) _LibraryPartnerExpansion(partners: partners) else const SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryManageTile extends StatelessWidget {
  const _LibraryManageTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        height: 36,
        width: 36,
        decoration: BoxDecoration(
          color: context.colorScheme.primary.withAlpha(24),
          borderRadius: const BorderRadius.all(Radius.circular(10)),
        ),
        child: Icon(icon, color: context.primaryColor, size: 20),
      ),
      title: Text(title, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(145)),
      ),
      onTap: onTap,
    );
  }
}

class _LibraryPartnerExpansion extends StatelessWidget {
  const _LibraryPartnerExpansion({required this.partners});

  final List<PartnerUserDto> partners;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: Container(
          height: 36,
          width: 36,
          decoration: BoxDecoration(
            color: context.colorScheme.primary.withAlpha(24),
            borderRadius: const BorderRadius.all(Radius.circular(10)),
          ),
          child: Icon(Icons.people_alt_outlined, color: context.primaryColor, size: 20),
        ),
        title: Text(
          'library_partner_library_title'.t(context: context, args: {'count': partners.length}),
          style: context.textTheme.titleSmall,
        ),
        subtitle: Text(
          'library_partner_library_subtitle'.t(context: context),
          style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(145)),
        ),
        children: partners.map((partner) {
          return ListTile(
            contentPadding: const EdgeInsets.only(left: 24, right: 18),
            leading: PartnerUserAvatar(partner: partner),
            title: const Text(
              "partner_list_user_photos",
              style: TextStyle(fontWeight: FontWeight.w500),
            ).t(context: context, args: {'user': partner.name}),
            onTap: () => context.pushRoute(DriftPartnerDetailRoute(partner: partner)),
          );
        }).toList(),
      ),
    );
  }
}

class _LibrarySectionHeader extends StatelessWidget {
  const _LibrarySectionHeader({required this.title, required this.subtitle, required this.icon});

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 32,
          width: 32,
          decoration: BoxDecoration(
            color: context.colorScheme.primary.withAlpha(18),
            borderRadius: const BorderRadius.all(Radius.circular(10)),
          ),
          child: Icon(icon, size: 18, color: context.primaryColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.t(context: context),
                style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                subtitle.t(context: context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(155)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: List.generate(4, (_) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.all(Radius.circular(10)),
          ),
        );
      }),
    );
  }
}

class _CardEmptyState extends StatelessWidget {
  const _CardEmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: context.colorScheme.onSurface.withAlpha(140)),
          const SizedBox(height: 8),
          Text(text, style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(150))),
        ],
      ),
    );
  }
}
// #pizcloud

// ignore: unused_element // pizcloud
class _ActionButtonGrid extends ConsumerWidget {
  const _ActionButtonGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTrashEnable = ref.watch(serverInfoProvider.select((state) => state.serverFeatures.trash));

    return SliverPadding(
      padding: const EdgeInsets.only(left: 16, top: 16, right: 16, bottom: 12),
      sliver: SliverToBoxAdapter(
        child: Column(
          children: [
            Row(
              children: [
                _ActionButton(
                  icon: Icons.favorite_outline_rounded,
                  onTap: () => context.pushRoute(const DriftFavoriteRoute()),
                  label: 'favorites'.t(context: context),
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.archive_outlined,
                  onTap: () => context.pushRoute(const DriftArchiveRoute()),
                  label: 'archived'.t(context: context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ActionButton(
                  icon: Icons.link_outlined,
                  onTap: () => context.pushRoute(const SharedLinkRoute()),
                  label: 'shared_links'.t(context: context),
                ),
                isTrashEnable ? const SizedBox(width: 8) : const SizedBox.shrink(),
                isTrashEnable
                    ? _ActionButton(
                        icon: Icons.delete_outline_rounded,
                        onTap: () => context.pushRoute(const DriftTrashRoute()),
                        label: 'trash'.t(context: context),
                      )
                    : const SizedBox.shrink(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.onTap, required this.label});

  final IconData icon;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FilledButton.icon(
        onPressed: onTap,
        label: Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: Text(label, style: TextStyle(color: context.colorScheme.onSurface, fontSize: 15)),
        ),
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          backgroundColor: context.colorScheme.surfaceContainerLow,
          alignment: Alignment.centerLeft,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(25)),
            side: BorderSide(color: context.colorScheme.onSurface.withAlpha(10), width: 1),
          ),
        ),
        icon: Icon(icon, color: context.primaryColor),
      ),
    );
  }
}

// ignore: unused_element // pizcloud
class _CollectionCards extends StatelessWidget {
  const _CollectionCards();

  @override
  Widget build(BuildContext context) {
    return const SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverToBoxAdapter(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [_PeopleCollectionCard(), _PlacesCollectionCard(), _LocalAlbumsCollectionCard()],
        ),
      ),
    );
  }
}

class _PeopleCollectionCard extends ConsumerWidget {
  const _PeopleCollectionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(driftGetAllPeopleProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth > 600;
        final widthFactor = isTablet ? 0.25 : 0.5;
        final size = context.width * widthFactor - 20.0;

        return GestureDetector(
          onTap: () => context.pushRoute(const DriftPeopleCollectionRoute()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: size,
                width: size,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  gradient: LinearGradient(
                    colors: [context.colorScheme.primary.withAlpha(30), context.colorScheme.primary.withAlpha(25)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: people.widgetWhen(
                  onLoading: () => const Center(child: CircularProgressIndicator()),
                  onData: (people) {
                    return GridView.count(
                      crossAxisCount: 2,
                      padding: const EdgeInsets.all(12),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      physics: const NeverScrollableScrollPhysics(),
                      children: people.take(4).map((person) {
                        return CircleAvatar(
                          backgroundImage: NetworkImage(
                            getFaceThumbnailUrl(person.id),
                            headers: ApiService.getRequestHeaders(),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'people'.t(context: context),
                  style: context.textTheme.titleSmall?.copyWith(
                    color: context.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlacesCollectionCard extends StatelessWidget {
  const _PlacesCollectionCard();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth > 600;
        final widthFactor = isTablet ? 0.25 : 0.5;
        final size = context.width * widthFactor - 20.0;

        return GestureDetector(
          onTap: () => context.pushRoute(DriftPlaceRoute(currentLocation: null)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: size,
                width: size,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(20)),
                    color: context.colorScheme.secondaryContainer.withAlpha(100),
                  ),
                  child: IgnorePointer(
                    child: MapThumbnail(
                      zoom: 8,
                      centre: const LatLng(21.44950, -157.91959),
                      showAttribution: false,
                      themeMode: context.isDarkTheme ? ThemeMode.dark : ThemeMode.light,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'places'.t(),
                  style: context.textTheme.titleSmall?.copyWith(
                    color: context.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LocalAlbumsCollectionCard extends ConsumerWidget {
  const _LocalAlbumsCollectionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(localAlbumProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth > 600;
        final widthFactor = isTablet ? 0.25 : 0.5;
        final size = context.width * widthFactor - 20.0;

        return GestureDetector(
          onTap: () => context.pushRoute(const DriftLocalAlbumsRoute()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: size,
                width: size,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(20)),
                    gradient: LinearGradient(
                      colors: [context.colorScheme.primary.withAlpha(30), context.colorScheme.primary.withAlpha(25)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: GridView.count(
                    crossAxisCount: 2,
                    padding: const EdgeInsets.all(12),
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    physics: const NeverScrollableScrollPhysics(),
                    children: albums.when(
                      data: (data) {
                        return data.take(4).map((album) {
                          return LocalAlbumThumbnail(albumId: album.id);
                        }).toList();
                      },
                      error: (error, _) {
                        return [
                          Center(child: Text('error_saving_image'.tr(args: [error.toString()]))),
                        ];
                      },
                      loading: () {
                        return [const Center(child: CircularProgressIndicator())];
                      },
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'on_this_device'.t(context: context),
                  style: context.textTheme.titleSmall?.copyWith(
                    color: context.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ignore: unused_element // pizcloud
class _QuickAccessButtonList extends ConsumerWidget {
  const _QuickAccessButtonList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerSharedWithAsync = ref.watch(driftSharedWithPartnerProvider);
    final partners = partnerSharedWithAsync.valueOrNull ?? [];

    return SliverPadding(
      padding: const EdgeInsets.only(left: 16, top: 12, right: 16, bottom: 32),
      sliver: SliverToBoxAdapter(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: context.colorScheme.onSurface.withAlpha(10), width: 1),
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            gradient: LinearGradient(
              colors: [
                context.colorScheme.primary.withAlpha(10),
                context.colorScheme.primary.withAlpha(15),
                context.colorScheme.primary.withAlpha(20),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(0),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(partners.isEmpty ? 20 : 0),
                    bottomRight: Radius.circular(partners.isEmpty ? 20 : 0),
                  ),
                ),
                leading: const Icon(Icons.folder_outlined, size: 26),
                title: Text(
                  'folders'.t(context: context),
                  style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
                ),
                onTap: () => context.pushRoute(FolderRoute()),
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded, size: 26),
                title: Text(
                  'locked_folder'.t(context: context),
                  style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
                ),
                onTap: () => context.pushRoute(const DriftLockedFolderRoute()),
              ),
              ListTile(
                leading: const Icon(Icons.group_outlined, size: 26),
                title: Text(
                  'partners'.t(context: context),
                  style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
                ),
                onTap: () => context.pushRoute(const DriftPartnerRoute()),
              ),
              _PartnerList(partners: partners),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartnerList extends StatelessWidget {
  const _PartnerList({required this.partners});

  final List<PartnerUserDto> partners;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(0),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: partners.length,
      shrinkWrap: true,
      itemBuilder: (context, index) {
        final partner = partners[index];
        final isLastItem = index == partners.length - 1;
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(isLastItem ? 20 : 0),
              bottomRight: Radius.circular(isLastItem ? 20 : 0),
            ),
          ),
          contentPadding: const EdgeInsets.only(left: 12.0, right: 18.0),
          leading: PartnerUserAvatar(partner: partner),
          title: const Text(
            "partner_list_user_photos",
            style: TextStyle(fontWeight: FontWeight.w500),
          ).t(context: context, args: {'user': partner.name}),
          onTap: () => context.pushRoute(DriftPartnerDetailRoute(partner: partner)),
        );
      },
    );
  }
}
