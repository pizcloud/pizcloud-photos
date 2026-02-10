import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart'; // pizcloud
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/presentation/widgets/album/album_selector.widget.dart';
import 'package:immich_mobile/providers/auth.provider.dart'; // pizcloud
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/pizcloud/album_transfer.provider.dart'; // pizcloud
import 'package:immich_mobile/presentation/pages/pizcloud/drift_album_transfer_inbox.page.dart'; // pizcloud
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/common/immich_sliver_app_bar.dart';

@RoutePage()
class DriftAlbumsPage extends ConsumerStatefulWidget {
  const DriftAlbumsPage({super.key});

  @override
  ConsumerState<DriftAlbumsPage> createState() => _DriftAlbumsPageState();
}

class _DriftAlbumsPageState extends ConsumerState<DriftAlbumsPage> {
  // pizcloud
  void _refreshOwnedTransferBadges() {
    final userId = ref.read(authProvider).userId;
    if (userId.isEmpty) {
      return;
    }

    // pizcloud: invalidate all owned album transfer providers on each trigger.
    // final albumIds = ownedAlbumIds(albums: ref.read(remoteAlbumProvider).albums, ownerId: userId);
    // for (final albumId in albumIds) {
    //   ref.invalidate(albumTransferByAlbumProvider(albumId));
    // }
    unawaited(
      refreshTransferIndicatorsForWidget(
        ref,
        albums: ref.read(remoteAlbumProvider).albums,
        ownerId: userId,
        reason: TransferRefreshReason.pageOpen,
      ),
    );
  }
  // #pizcloud

  // pizcloud
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ref.invalidate(albumIncomingTransfersProvider);
      _refreshOwnedTransferBadges(); // pizcloud
    });
  }
  // #pizcloud

  Future<void> onRefresh() async {
    // ref.invalidate(albumIncomingTransfersProvider); // pizcloud
    await ref.read(remoteAlbumProvider.notifier).refresh();
    // pizcloud
    final userId = ref.read(authProvider).userId;
    if (userId.isEmpty) {
      return;
    }
    await refreshTransferIndicatorsForWidget(
      ref,
      albums: ref.read(remoteAlbumProvider).albums,
      ownerId: userId,
      reason: TransferRefreshReason.pullToRefresh,
      force: true,
    );
    // #pizcloud
  }

  @override
  Widget build(BuildContext context) {
    final incomingTransfersAsync = ref.watch(albumIncomingTransfersProvider); // pizcloud

    return RefreshIndicator(
      onRefresh: onRefresh,
      edgeOffset: 100,
      child: CustomScrollView(
        slivers: [
          ImmichSliverAppBar(
            snap: false,
            floating: false,
            pinned: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 28),
                onPressed: () => context.pushRoute(const DriftCreateAlbumRoute()),
              ),
            ],
            showUploadButton: false,
          ),
          // pizcloud
          SliverToBoxAdapter(
            child: incomingTransfersAsync.maybeWhen(
              data: (items) {
                if (items.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.swap_horiz_rounded),
                      title: Text('transfer_inbox_banner_title'.tr(namedArgs: {'count': '${items.length}'})),
                      // title: Text('transfer_inbox_banner_title'.tr(args: ['${items.length}'])),
                      subtitle: Text('transfer_inbox_banner_subtitle'.tr()),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute(builder: (_) => const DriftAlbumTransferInboxPage())),
                    ),
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
          ),
          // #pizcloud
          AlbumSelector(
            onAlbumSelected: (album) {
              context.router.push(RemoteAlbumRoute(album: album));
            },
          ),
        ],
      ),
    );
  }
}
