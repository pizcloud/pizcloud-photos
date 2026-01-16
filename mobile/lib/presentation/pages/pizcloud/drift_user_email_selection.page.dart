import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/album/pizcloud/shared_email.model.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/extensions/asyncvalue_extensions.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/pizcloud/album_share_email.provider.dart';
import 'package:immich_mobile/providers/infrastructure/remote_album.provider.dart';
import 'package:immich_mobile/services/pizcloud/album_share_email_api.service.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';

@RoutePage()
class DriftUserEmailSelectionPage extends HookConsumerWidget {
  final RemoteAlbum album;

  const DriftUserEmailSelectionPage({super.key, required this.album});

  bool _isValidEmail(String value) {
    final email = value.trim();
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return regex.hasMatch(email);
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharedEmailsAsync = ref.watch(albumSharedEmailsProvider(album.id));
    final sharedUsersAsync = ref.watch(remoteAlbumSharedUsersProvider(album.id));

    final emailController = useTextEditingController();
    final isSubmitting = useState(false);
    final selectedEmails = useState<Set<String>>({});
    final sharedItems = sharedEmailsAsync.asData?.value;

    String normalizeEmail(String value) => value.trim().toLowerCase();

    bool isSelected(String email) => selectedEmails.value.contains(normalizeEmail(email));

    void toggleSelection(String email) {
      final normalized = normalizeEmail(email);
      final next = {...selectedEmails.value};
      if (next.contains(normalized)) {
        next.remove(normalized);
      } else {
        next.add(normalized);
      }
      selectedEmails.value = next;
    }

    useEffect(() {
      if (sharedItems == null) {
        return null;
      }

      final sharedUsers = sharedUsersAsync.asData?.value ?? const <UserDto>[];
      final sharedUserEmails = sharedUsers.map((user) => normalizeEmail(user.email)).toSet();
      final available = sharedItems.map((item) => normalizeEmail(item.email)).toSet();
      if (selectedEmails.value.isEmpty && available.isNotEmpty) {
        selectedEmails.value = available.intersection(sharedUserEmails);
      } else if (selectedEmails.value.isNotEmpty) {
        final next = selectedEmails.value.intersection(available);
        if (next.length != selectedEmails.value.length) {
          selectedEmails.value = next;
        }
      }

      return null;
    }, [sharedItems, sharedUsersAsync.asData?.value]);
    // Old behavior: auto-select all saved emails on first load.
    // if (selectedEmails.value.isEmpty && available.isNotEmpty) {
    //   selectedEmails.value = available;
    // }

    Future<void> onApply() async {
      final raw = emailController.text.trim();
      final email = raw.toLowerCase();

      if (email.isEmpty) {
        _toast(context, 'please_enter_email'.tr());
        return;
      }
      if (!_isValidEmail(email)) {
        _toast(context, 'invalid_email'.tr());
        return;
      }

      try {
        isSubmitting.value = true;
        await AlbumShareEmailApiService.addSharedEmail(albumId: album.id, email: email);

        emailController.clear();
        selectedEmails.value = {...selectedEmails.value, email};
        ref.invalidate(albumSharedEmailsProvider(album.id));
        _toast(context, 'add_successfully'.tr());
      } catch (_) {
        _toast(context, 'add_failed'.tr());
      } finally {
        isSubmitting.value = false;
      }
    }

    Future<void> onRemove(String email) async {
      try {
        isSubmitting.value = true;
        await AlbumShareEmailApiService.removeSharedEmail(albumId: album.id, email: email);
        selectedEmails.value = {...selectedEmails.value}..remove(normalizeEmail(email));
        ref.invalidate(albumSharedEmailsProvider(album.id));
        _toast(context, 'removed'.tr());
      } catch (_) {
        _toast(context, 'remove_failed'.tr());
      } finally {
        isSubmitting.value = false;
      }
    }

    Future<void> onUnshare(UserDto user) async {
      try {
        isSubmitting.value = true;
        await ref.read(remoteAlbumProvider.notifier).removeUser(album.id, user.id);
        ref.invalidate(remoteAlbumSharedUsersProvider(album.id));
        _toast(context, 'removed'.tr());
      } catch (_) {
        _toast(context, 'remove_failed'.tr());
      } finally {
        isSubmitting.value = false;
      }
    }

    void onDone(List<SharedEmailDto> items) {
      final selected = items.where((item) => isSelected(item.email)).map((item) => normalizeEmail(item.email)).toList();
      context.maybePop(selected);
    }

    Widget buildInput() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onApply(),
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
                onPressed: isSubmitting.value ? null : onApply,
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

    Widget buildChips(List<SharedEmailDto> items) {
      if (items.isEmpty) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text('no_shared_emails_yet'.tr(), style: const TextStyle(fontSize: 13, color: Colors.grey)),
        );
      }

      final selected = items.where((item) => isSelected(item.email)).toList();
      if (selected.isEmpty) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final x in selected)
              Chip(
                backgroundColor: context.primaryColor.withValues(alpha: 0.12),
                label: Text(x.email, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      );
    }

    Widget buildList(List<SharedEmailDto> items, Map<String, UserDto> sharedUserByEmail) {
      return ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          final selected = isSelected(item.email);
          final sharedUser = sharedUserByEmail[normalizeEmail(item.email)];
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
            subtitle: Text(
              DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt.toLocal()),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sharedUser != null)
                  IconButton(
                    icon: const Icon(Icons.link_off_rounded),
                    onPressed: isSubmitting.value ? null : () => onUnshare(sharedUser),
                    tooltip: 'remove_user'.tr(),
                  ),
                if (sharedUser == null)
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: selected ? context.primaryColor : Colors.grey,
                  ),
                if (sharedUser == null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: isSubmitting.value ? null : () => onRemove(item.email),
                    tooltip: 'remove'.tr(),
                  ),
              ],
            ),
            onTap: () => toggleSelection(item.email),
          );
        },
      );
    }

    final canDone = sharedEmailsAsync.maybeWhen(
      data: (items) => items.any((item) => isSelected(item.email)),
      orElse: () => false,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('invite_to_album').tr(),
        elevation: 0,
        centerTitle: false,
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => context.maybePop(null)),
        actions: [
          // TextButton(
          //   onPressed: canDone
          //       ? () {
          //           final items = sharedEmailsAsync.value ?? const <SharedEmailDto>[];
          //           onDone(items);
          //         }
          //       : null,
          //   child: const Text("share", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)).tr(),
          // ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 15)),
                onPressed: canDone
                    ? () {
                        final items = sharedEmailsAsync.value ?? const <SharedEmailDto>[];
                        onDone(items);
                      }
                    : null,
                icon: isSubmitting.value
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                label: Text('share'.tr()),
              ),
            ),
          ),
        ],
      ),
      body: sharedEmailsAsync.widgetWhen(
        onData: (items) {
          final sharedUserByEmail = sharedUsersAsync.maybeWhen(
            data: (users) => {for (final user in users) normalizeEmail(user.email): user},
            orElse: () => <String, UserDto>{},
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'save_email_then_share_hint'.tr(),
                  style: const TextStyle(fontSize: 14, color: Color.fromARGB(255, 112, 111, 111)),
                ),
              ),
              buildInput(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'shared_with'.tr(),
                  style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold),
                ),
              ),
              buildChips(items),
              const Divider(height: 1),
              Expanded(child: buildList(items, sharedUserByEmail)),
            ],
          );
        },
        onLoading: () => const Center(child: CircularProgressIndicator()),
        onError: (e, _) => Center(
          child: Padding(padding: const EdgeInsets.all(16), child: Text('failed_to_load_shared_emails'.tr())),
        ),
      ),
    );
  }
}
