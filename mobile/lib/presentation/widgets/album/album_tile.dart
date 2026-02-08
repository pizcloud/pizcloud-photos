import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'; // pizcloud
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/album/pizcloud/album_transfer.model.dart'; // pizcloud
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/pages/common/large_leading_tile.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail.widget.dart';
import 'package:immich_mobile/providers/pizcloud/album_transfer.provider.dart'; // pizcloud

class AlbumTile extends ConsumerWidget {
  const AlbumTile({super.key, required this.album, required this.isOwner, this.onAlbumSelected});

  final RemoteAlbum album;
  final bool isOwner;
  final Function(RemoteAlbum)? onAlbumSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // pizcloud
    final pendingTransferAsync = isOwner
        ? ref.watch(albumTransferByAlbumProvider(album.id))
        : const AsyncValue<AlbumTransferDto?>.data(null);
    final hasPendingTransfer =
        isOwner &&
        pendingTransferAsync.maybeWhen(data: (transfer) => transfer?.isPending ?? false, orElse: () => false);

    Widget buildPendingBadge() {
      final badgeAccent = context.logoYellow;
      final badgeFill = badgeAccent.withValues(alpha: context.isDarkTheme ? 0.36 : 0.28);

      return Positioned(
        top: 6,
        left: 6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            // Old styling (kept for comparison):
            // color: context.colorScheme.tertiary.withValues(alpha: 0.18),
            // border: Border.all(color: context.colorScheme.tertiary.withValues(alpha: 0.5)),
            color: badgeFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: badgeAccent.withValues(alpha: 0.9)),
          ),
          child: Icon(Icons.swap_horiz_rounded, size: 14, color: badgeAccent),
        ),
      );
    }

    Widget buildThumbnail() {
      // Old leading (kept for comparison):
      // return album.thumbnailAssetId != null
      //     ? ClipRRect(
      //         borderRadius: const BorderRadius.all(Radius.circular(15)),
      //         child: SizedBox(width: 80, height: 80, child: Thumbnail.remote(remoteId: album.thumbnailAssetId!)),
      //       )
      //     : SizedBox(
      //         width: 80,
      //         height: 80,
      //         child: Container(
      //           decoration: BoxDecoration(
      //             color: context.colorScheme.surfaceContainer,
      //             borderRadius: const BorderRadius.all(Radius.circular(16)),
      //             border: Border.all(color: context.colorScheme.outline.withAlpha(50), width: 1),
      //           ),
      //           child: const Icon(Icons.photo_album_rounded, size: 24, color: Colors.grey),
      //         ),
      //       );

      return ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(15)),
        child: SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            fit: StackFit.expand,
            children: [
              album.thumbnailAssetId != null
                  ? Thumbnail.remote(remoteId: album.thumbnailAssetId!)
                  : Container(
                      decoration: BoxDecoration(
                        color: context.colorScheme.surfaceContainer,
                        borderRadius: const BorderRadius.all(Radius.circular(16)),
                        border: Border.all(color: context.colorScheme.outline.withAlpha(50), width: 1),
                      ),
                      child: const Icon(Icons.photo_album_rounded, size: 24, color: Colors.grey),
                    ),
              if (hasPendingTransfer) buildPendingBadge(),
            ],
          ),
        ),
      );
    }
    // #pizcloud

    return LargeLeadingTile(
      title: Text(
        album.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      // pizcloud
      // subtitle: Text(
      //   '${'items_count'.t(context: context, args: {'count': album.assetCount})} • ${isOwner ? 'owned'.t(context: context) : 'shared_by_user'.t(context: context, args: {'user': album.ownerName})}',
      //   overflow: TextOverflow.ellipsis,
      //   style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceSecondary),
      // ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPendingTransfer) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'transfer_pending_short'.t(context: context),
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
          ],
          Text(
            '${'items_count'.t(context: context, args: {'count': album.assetCount})} • ${isOwner ? 'owned'.t(context: context) : 'shared_by_user'.t(context: context, args: {'user': album.ownerName})}',
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceSecondary),
          ),
        ],
      ),
      // #pizcloud
      onTap: () => onAlbumSelected?.call(album),
      leadingPadding: const EdgeInsets.only(right: 16),
      leading: buildThumbnail(),
    );
  }
}
