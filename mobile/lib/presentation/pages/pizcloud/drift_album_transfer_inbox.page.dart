import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/pizcloud/album_transfer.model.dart';
import 'package:immich_mobile/extensions/asyncvalue_extensions.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/remote_album.provider.dart';
import 'package:immich_mobile/providers/pizcloud/album_transfer.provider.dart';
import 'package:immich_mobile/services/pizcloud/album_transfer_api.service.dart';
import 'package:immich_mobile/utils/bytes_units.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

@RoutePage()
class DriftAlbumTransferInboxPage extends ConsumerWidget {
  const DriftAlbumTransferInboxPage({super.key});

  Future<void> _handleAccept(BuildContext context, WidgetRef ref, AlbumTransferDto transfer) async {
    final confirmed = await showPlatformDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('transfer_accept_title'.tr()),
        content: Text('transfer_accept_confirm'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text('cancel'.tr())),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text('confirm'.tr())),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      final apiService = ref.read(apiServiceProvider);
      await AlbumTransferApiService.acceptTransfer(apiService, transfer.id);
      ref.invalidate(albumIncomingTransfersProvider);
      await ref.read(remoteAlbumServiceProvider).syncAlbumFromServer(transfer.albumId);
      ref.invalidate(remoteAlbumSharedUsersProvider(transfer.albumId));
      await ref.read(remoteAlbumProvider.notifier).refresh();
      ImmichToast.show(context: context, msg: 'transfer_accept_success'.tr(), toastType: ToastType.success);
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('insufficient_quota')) {
        ImmichToast.show(context: context, msg: 'transfer_insufficient_quota'.tr(), toastType: ToastType.info);
        return;
      }
      if (message.contains('asset_conflict')) {
        ImmichToast.show(context: context, msg: 'transfer_asset_conflict'.tr(), toastType: ToastType.info);
        return;
      }
      ImmichToast.show(context: context, msg: 'transfer_request_failed'.tr(), toastType: ToastType.error);
    }
  }

  Future<void> _handleDecline(BuildContext context, WidgetRef ref, AlbumTransferDto transfer) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      await AlbumTransferApiService.declineTransfer(apiService, transfer.id);
      ref.invalidate(albumIncomingTransfersProvider);
      ImmichToast.show(context: context, msg: 'transfer_decline_success'.tr(), toastType: ToastType.success);
    } catch (_) {
      ImmichToast.show(context: context, msg: 'transfer_request_failed'.tr(), toastType: ToastType.error);
    }
  }

  Widget _buildTransferTile(BuildContext context, WidgetRef ref, AlbumTransferDto transfer) {
    final sizeLabel = formatBytes(transfer.totalBytes);
    final countLabel = '${transfer.assetCount}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(transfer.albumName, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'transfer_from_user'.tr(namedArgs: {'email': transfer.fromUser.email}),
              style: const TextStyle(fontSize: 13),
            ),
            // Text('transfer_from_user'.tr(args: [transfer.fromUser.email]), style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Text(
              'transfer_album_size'.tr(namedArgs: {'capacity': sizeLabel, 'count': countLabel}),
              style: const TextStyle(fontSize: 12),
            ),
            // Text('transfer_album_size'.tr(args: [sizeLabel, countLabel]), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _handleDecline(context, ref, transfer),
                  child: Text('transfer_decline'.tr()),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _handleAccept(context, ref, transfer),
                  child: Text('transfer_accept'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfersAsync = ref.watch(albumIncomingTransfersProvider);

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text('transfer_inbox_title'.tr()),
        material: (_, __) => MaterialAppBarData(centerTitle: false),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.maybePop()),
      ),
      body: transfersAsync.widgetWhen(
        onData: (items) {
          if (items.isEmpty) {
            return Center(child: Text('transfer_inbox_empty'.tr()));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) => _buildTransferTile(context, ref, items[index]),
          );
        },
        onLoading: () => const Center(child: CircularProgressIndicator()),
        onError: (e, _) => Center(child: Text('transfer_request_failed'.tr())),
      ),
    );
  }
}
