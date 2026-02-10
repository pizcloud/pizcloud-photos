import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/album/pizcloud/album_transfer.model.dart';
import 'package:immich_mobile/domain/models/album/pizcloud/shared_email.model.dart';
import 'package:immich_mobile/extensions/asyncvalue_extensions.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/utils/album_share_email.utils.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/pizcloud/album_share_email.provider.dart';
import 'package:immich_mobile/providers/pizcloud/album_transfer.provider.dart';
import 'package:immich_mobile/services/pizcloud/album_share_email_api.service.dart';
import 'package:immich_mobile/services/pizcloud/album_transfer_api.service.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

@RoutePage()
class DriftAlbumTransferOwnershipPage extends HookConsumerWidget {
  final RemoteAlbum album;

  const DriftAlbumTransferOwnershipPage({super.key, required this.album});

  bool _isValidEmail(String value) {
    final email = value.trim();
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return regex.hasMatch(email);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharedEmailsAsync = ref.watch(albumSharedEmailsProvider(album.id));
    final pendingTransferAsync = ref.watch(albumTransferByAlbumProvider(album.id));
    final pendingTransfer = pendingTransferAsync.asData?.value;
    final hasPendingTransfer = pendingTransfer != null && pendingTransfer.isPending;

    final emailController = useTextEditingController();
    final isSubmitting = useState(false);
    final selectedEmail = useState<String?>(null);

    String normalizeEmail(String value) => value.trim().toLowerCase();

    bool isSelected(String email) => selectedEmail.value == normalizeEmail(email);

    void setSelected(String email) {
      final normalized = normalizeEmail(email);
      if (selectedEmail.value == normalized) {
        selectedEmail.value = null;
      } else {
        selectedEmail.value = normalized;
      }
    }

    Future<void> onApply() async {
      final raw = emailController.text.trim();
      final email = raw.toLowerCase();

      if (email.isEmpty) {
        ImmichToast.show(context: context, msg: 'please_enter_email'.tr(), toastType: ToastType.info);
        return;
      }
      if (!_isValidEmail(email)) {
        ImmichToast.show(context: context, msg: 'invalid_email'.tr(), toastType: ToastType.info);
        return;
      }

      try {
        isSubmitting.value = true;
        await AlbumShareEmailApiService.addSharedEmail(albumId: album.id, email: email);
        emailController.clear();
        selectedEmail.value = email;
        ref.invalidate(albumSharedEmailsProvider(album.id));
        ImmichToast.show(context: context, msg: 'add_successfully'.tr(), toastType: ToastType.success);
      } catch (_) {
        ImmichToast.show(context: context, msg: 'add_failed'.tr(), toastType: ToastType.error);
      } finally {
        isSubmitting.value = false;
      }
    }

    Future<void> onRemove(String email) async {
      try {
        isSubmitting.value = true;
        await AlbumShareEmailApiService.removeSharedEmail(albumId: album.id, email: email);
        if (isSelected(email)) {
          selectedEmail.value = null;
        }
        ref.invalidate(albumSharedEmailsProvider(album.id));
        ImmichToast.show(context: context, msg: 'removed'.tr(), toastType: ToastType.success);
      } catch (_) {
        ImmichToast.show(context: context, msg: 'remove_failed'.tr(), toastType: ToastType.error);
      } finally {
        isSubmitting.value = false;
      }
    }

    Future<void> onRequestTransfer() async {
      final email = selectedEmail.value;
      if (email == null || email.isEmpty) {
        ImmichToast.show(context: context, msg: 'transfer_select_email'.tr(), toastType: ToastType.info);
        return;
      }

      try {
        isSubmitting.value = true;
        final apiService = ref.read(apiServiceProvider);
        final resolution = await resolveShareUserIdsByEmail(apiService: apiService, albumId: album.id, emails: [email]);

        if (resolution.missingEmails.isNotEmpty) {
          final preview = resolution.missingEmails.take(3).join(', ');
          final suffix = resolution.missingEmails.length > 3 ? '...' : '';
          ImmichToast.show(context: context, msg: 'Not found in Pizcloud: $preview$suffix', toastType: ToastType.info);
          return;
        }

        if (resolution.userIds.isEmpty) {
          ImmichToast.show(context: context, msg: 'transfer_user_not_found'.tr(), toastType: ToastType.info);
          return;
        }

        await AlbumTransferApiService.requestTransfer(
          apiService,
          albumId: album.id,
          toUserId: resolution.userIds.first,
        );

        ref.invalidate(albumTransferByAlbumProvider(album.id));
        ImmichToast.show(context: context, msg: 'transfer_request_sent'.tr(), toastType: ToastType.success);
      } catch (e) {
        ImmichToast.show(context: context, msg: 'transfer_request_failed'.tr(), toastType: ToastType.error);
      } finally {
        isSubmitting.value = false;
      }
    }

    Future<void> onCancelTransfer(AlbumTransferDto transfer) async {
      final confirmed = await showPlatformDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('transfer_cancel_title'.tr()),
          content: Text('transfer_cancel_confirm'.tr()),
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
        isSubmitting.value = true;
        final apiService = ref.read(apiServiceProvider);
        await AlbumTransferApiService.cancelTransfer(apiService, album.id);
        ref.invalidate(albumTransferByAlbumProvider(album.id));
        ImmichToast.show(context: context, msg: 'transfer_request_canceled'.tr(), toastType: ToastType.success);
      } catch (_) {
        ImmichToast.show(context: context, msg: 'transfer_request_failed'.tr(), toastType: ToastType.error);
      } finally {
        isSubmitting.value = false;
      }
    }

    Widget buildInput(bool disabled) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => disabled ? null : onApply(),
                enabled: !disabled,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'enter_email_to_share'.tr(),
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 30,
              child: ElevatedButton.icon(
                onPressed: disabled || isSubmitting.value ? null : onApply,
                icon: isSubmitting.value
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_rounded),
                label: Text('add'.tr()),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildList(List<SharedEmailDto> items, bool disabled) {
      if (items.isEmpty) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text('no_shared_emails_yet'.tr(), style: const TextStyle(fontSize: 13, color: Colors.grey)),
        );
      }

      return ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          final selected = isSelected(item.email);
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: context.primaryColor.withValues(alpha: 0.12),
              child: Text(
                item.email.isNotEmpty ? item.email[0].toUpperCase() : '?',
                style: TextStyle(color: context.primaryColor, fontWeight: FontWeight.bold),
              ),
            ),
            dense: true,
            title: Text(item.email, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!disabled)
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: selected ? context.primaryColor : Colors.grey,
                  ),
                if (!disabled)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: isSubmitting.value ? null : () => onRemove(item.email),
                    tooltip: 'remove'.tr(),
                  ),
              ],
            ),
            onTap: disabled ? null : () => setSelected(item.email),
          );
        },
      );
    }

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text('transfer_ownership'.tr()),
        material: (_, __) => MaterialAppBarData(elevation: 0, centerTitle: false),
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => context.maybePop()),
      ),
      body: pendingTransferAsync.widgetWhen(
        onData: (pendingTransfer) {
          final disabled = pendingTransfer != null && pendingTransfer.isPending;

          return sharedEmailsAsync.widgetWhen(
            onData: (items) {
              if (pendingTransfer != null && pendingTransfer.isPending) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Card(
                        elevation: 0,
                        color: context.colorScheme.surfaceContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('transfer_pending_title'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Builder(
                                builder: (context) {
                                  final email = pendingTransfer.toUser.email;
                                  final description = 'transfer_pending_description'.tr(namedArgs: {'email': email});
                                  final index = description.indexOf(email);
                                  if (index == -1) {
                                    return Text(description, style: const TextStyle(fontSize: 13));
                                  }
                                  return Text.rich(
                                    TextSpan(
                                      style: const TextStyle(fontSize: 13),
                                      children: [
                                        TextSpan(text: description.substring(0, index)),
                                        TextSpan(
                                          text: email,
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                        TextSpan(text: description.substring(index + email.length)),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: isSubmitting.value ? null : () => onCancelTransfer(pendingTransfer),
                                  icon: const Icon(Icons.cancel_outlined),
                                  label: Text('transfer_cancel'.tr()),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.colorScheme.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: context.colorScheme.primary.withValues(alpha: 0.12),
                                  ),
                                  child: Icon(Icons.swap_horiz_rounded, color: context.colorScheme.primary, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'transfer_ownership_hint'.tr(),
                                    style: TextStyle(fontSize: 14, color: context.colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              decoration: BoxDecoration(
                                color: context.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: context.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline_rounded, color: context.colorScheme.primary, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'transfer_warning'.tr(),
                                      style: TextStyle(fontSize: 12, color: context.colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selectedEmail.value != null && selectedEmail.value!.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                decoration: BoxDecoration(
                                  color: context.colorScheme.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: context.colorScheme.primary.withValues(alpha: 0.35)),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Icon(Icons.check_circle_rounded, color: context.colorScheme.primary, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        selectedEmail.value!,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: context.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.center,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  minimumSize: const Size(0, 30),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                onPressed: isSubmitting.value || hasPendingTransfer ? null : onRequestTransfer,
                                icon: isSubmitting.value
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.swap_horiz_rounded, size: 18),
                                label: Text('transfer_send'.tr()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  buildInput(disabled),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'saved_list'.tr(),
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: buildList(items, disabled)),
                ],
              );
            },
            onLoading: () => const Center(child: CircularProgressIndicator()),
            onError: (e, _) => Center(
              child: Padding(padding: const EdgeInsets.all(16), child: Text('failed_to_load_shared_emails'.tr())),
            ),
          );
        },
        onLoading: () => const Center(child: CircularProgressIndicator()),
        onError: (e, _) => Center(
          child: Padding(padding: const EdgeInsets.all(16), child: Text('transfer_request_failed'.tr())),
        ),
      ),
    );
  }
}
