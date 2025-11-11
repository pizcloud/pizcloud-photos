import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/media_permission.provider.dart';
import '../../services/media_permission_service.dart';

class MediaPermissionBanner extends ConsumerWidget {
  const MediaPermissionBanner({super.key});

  bool _shouldShow(MediaPermState s) {
    // Display if not FULL (Android 13/14), or NONE (≤12).
    // LEGACY (≤12 with READ_EXTERNAL_STORAGE) is considered sufficient.
    return s == MediaPermState.none || s == MediaPermState.limited;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mediaPermissionProvider);

    if (!_shouldShow(state)) return const SizedBox.shrink();

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.photo_library_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text('photo_access_permission_is_required', style: Theme.of(context).textTheme.bodyMedium).tr(),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () async {
                  final (ok, permanentlyDenied) = await ref.read(mediaPermissionProvider.notifier).requestAndRefresh();

                  if (ok) return;

                  if (permanentlyDenied) {
                    // The system has blocked the permission dialog → guide to open Settings
                    _showGoToSettingsDialog(context, ref);
                  } else {
                    // The user has kept 'Allow limited' or just tapped 'Don’t allow'
                    // => suggest opening Settings to upgrade to 'Allow all'.
                    _showUpgradeFromLimitedDialog(context, ref);
                  }
                },
                child: const Text('grant_permission_now').tr(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGoToSettingsDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('open_settings_to_grant_permission').tr(),
        content: Text(
          '${tr('you_have_denied_permission_multiple_times')}\n\n'
          '${tr('please_open_the_app_settings_page_and_enable_photos_videos')}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('do_it_later').tr()),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await ref.read(mediaPermissionProvider.notifier).openSettings();
            },
            child: const Text('open_settings').tr(),
          ),
        ],
      ),
    );
  }

  void _showUpgradeFromLimitedDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('allow_all_is_required').tr(),
        content: Text(
          '${tr('you_are_currently_on_allow_limited_access')}\n\n'
          '${tr('to_automatically_back_up_your_entire_library')}\n\n'
          '${tr('you_can_try_the_grant_permission_button_again')}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('close').tr()),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await ref.read(mediaPermissionProvider.notifier).openSettings();
            },
            child: const Text('open_settings').tr(),
          ),
        ],
      ),
    );
  }
}
