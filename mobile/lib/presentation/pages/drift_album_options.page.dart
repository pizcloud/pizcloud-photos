import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/utils/platform_sheet.dart';
import 'package:immich_mobile/presentation/pages/drift_user_selection.page.dart';
import 'package:immich_mobile/presentation/utils/album_share_email.utils.dart'; // pizcloud
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/current_album.provider.dart';
// import 'package:immich_mobile/providers/infrastructure/db.provider.dart'; // pizcloud // UPDATE
import 'package:immich_mobile/providers/api.provider.dart'; // pizcloud
import 'package:immich_mobile/providers/infrastructure/remote_album.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/widgets/common/user_circle_avatar.dart';

@RoutePage()
class DriftAlbumOptionsPage extends HookConsumerWidget {
  final RemoteAlbum album;
  const DriftAlbumOptionsPage({super.key, required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharedUsersAsync = ref.watch(remoteAlbumSharedUsersProvider(album.id));
    final userId = ref.watch(authProvider).userId;
    final activityEnabled = useState(album.isActivityEnabled);
    final isOwner = album.ownerId == userId;
    // pizcloud: For shared viewers, mask names/emails in Options.
    final maskForSharedViewer = !isOwner;

    String maskEmail(String email) {
      final normalized = email.trim().toLowerCase();
      final atIndex = normalized.indexOf('@');
      if (atIndex <= 0) {
        return '****@';
      }
      return '****@${normalized.substring(atIndex + 1)}';
    }

    String displayName(UserDto user) {
      if (!maskForSharedViewer || user.id == userId) {
        return user.name;
      }
      return '****';
    }

    String displayEmail(UserDto user) {
      if (!maskForSharedViewer || user.id == userId) {
        return user.email;
      }
      return maskEmail(user.email);
    }
    // #pizcloud

    void showErrorMessage() {
      context.pop();
      ImmichToast.show(
        context: context,
        msg: "shared_album_section_people_action_error".t(context: context),
        toastType: ToastType.error,
        gravity: ToastGravity.BOTTOM,
      );
    }

    void leaveAlbum() async {
      try {
        await ref.read(remoteAlbumProvider.notifier).leaveAlbum(album.id, userId: userId);
        unawaited(context.navigateTo(const DriftAlbumsRoute()));
      } catch (_) {
        showErrorMessage();
      }
    }

    void removeUserFromAlbum(UserDto user) async {
      try {
        await ref.read(remoteAlbumProvider.notifier).removeUser(album.id, user.id);
        ref.invalidate(remoteAlbumSharedUsersProvider(album.id));
      } catch (_) {
        showErrorMessage();
      }

      context.pop();
    }

    Future<void> addUsers() async {
      // pizcloud
      // Old flow: pick users from Drift and add directly by userId.
      // final newUsers = await context.pushRoute<List<String>>(DriftUserSelectionRoute(album: album));
      // if (newUsers == null || newUsers.isEmpty) {
      //   return;
      // }
      // await ref.read(remoteAlbumProvider.notifier).addUsers(album.id, newUsers);

      final selectedEmails = await context.pushRoute<List<String>>(DriftUserEmailSelectionRoute(album: album));

      if (selectedEmails == null || selectedEmails.isEmpty) {
        return;
      }

      try {
        // final drift = ref.read(driftProvider);
        // final resolution = await resolveShareUserIdsByEmail(drift: drift, emails: selectedEmails);
        final apiService = ref.read(apiServiceProvider);
        final resolution = await resolveShareUserIdsByEmail(
          apiService: apiService,
          albumId: album.id,
          emails: selectedEmails,
        );
        final sharedUsers = await ref.read(remoteAlbumSharedUsersProvider(album.id).future);
        final existingIds = {...sharedUsers.map((user) => user.id), album.ownerId};
        final userIdsToAdd = resolution.userIds.where((id) => !existingIds.contains(id)).toList();

        if (resolution.missingEmails.isNotEmpty) {
          final preview = resolution.missingEmails.take(3).join(', ');
          final suffix = resolution.missingEmails.length > 3 ? '...' : '';
          ImmichToast.show(context: context, msg: 'Not found in Pizcloud: $preview$suffix', toastType: ToastType.info);
        }

        if (userIdsToAdd.isEmpty) {
          ImmichToast.show(
            context: context,
            msg: 'No new users to add from selected emails.',
            toastType: ToastType.info,
          );
          return;
        }

        await ref.read(remoteAlbumProvider.notifier).addUsers(album.id, userIdsToAdd);

        if (userIdsToAdd.isNotEmpty) {
          ImmichToast.show(
            context: context,
            msg: "users_added_to_album_count".t(context: context, args: {'count': userIdsToAdd.length}),
            toastType: ToastType.success,
          );
        }

        ref.invalidate(remoteAlbumSharedUsersProvider(album.id));
      } catch (e) {
        ImmichToast.show(
          context: context,
          msg: "Failed to add users to album: ${e.toString()}",
          toastType: ToastType.error,
        );
      }
      // #pizcloud
    }

    void handleUserClick(UserDto user) {
      var actions = [];

      if (user.id == userId) {
        actions = [
          ListTile(
            leading: const Icon(Icons.exit_to_app_rounded),
            title: const Text("leave_album").t(context: context),
            onTap: leaveAlbum,
          ),
        ];
      }

      if (isOwner) {
        actions = [
          ListTile(
            leading: const Icon(Icons.person_remove_rounded),
            title: const Text("remove_user").t(context: context),
            onTap: () => removeUserFromAlbum(user),
          ),
        ];
      }

      showPlatformModalSheet(
        context: context,
        material: MaterialModalSheetData(
          backgroundColor: context.colorScheme.surfaceContainer,
          isScrollControlled: false,
          useSafeArea: true,
        ),
        builder: (context) {
          return platformSheetWrapper(
            context,
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [...actions]),
            ),
          );
        },
      );
    }

    buildOwnerInfo() {
      if (isOwner) {
        final owner = ref.watch(currentUserProvider);
        return ListTile(
          // pizcloud
          leading: owner != null ? UserCircleAvatar(user: owner) : const SizedBox(),
          title: Text(album.ownerName, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(owner?.email ?? "", style: TextStyle(color: context.colorScheme.onSurfaceSecondary)),
          // Old behavior: always show full owner name/email.
          // title: Text(album.ownerName, style: const TextStyle(fontWeight: FontWeight.w500)),
          // subtitle: Text(owner?.email ?? "", style: TextStyle(color: context.colorScheme.onSurfaceSecondary)),
          // #pizcloud
          trailing: Text("owner", style: context.textTheme.labelLarge).t(context: context),
        );
      } else {
        final usersProvider = ref.watch(driftUsersProvider);
        return usersProvider.maybeWhen(
          data: (users) {
            final user = users.firstWhereOrNull((u) => u.id == album.ownerId);

            if (user == null) {
              return const SizedBox();
            }

            return ListTile(
              // pizcloud
              leading: UserCircleAvatar(user: user, radius: 22),
              title: Text(displayName(user), style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(displayEmail(user), style: TextStyle(color: context.colorScheme.onSurfaceSecondary)),
              // Old behavior: always show full owner name/email.
              // title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w500)),
              // subtitle: Text(user.email, style: TextStyle(color: context.colorScheme.onSurfaceSecondary)),
              // #pizcloud
              trailing: Text("owner", style: context.textTheme.labelLarge).t(context: context),
            );
          },
          orElse: () => const SizedBox(),
        );
      }
    }

    buildSharedUsersList() {
      return sharedUsersAsync.maybeWhen(
        data: (sharedUsers) => ListView.builder(
          primary: false,
          shrinkWrap: true,
          itemCount: sharedUsers.length,
          itemBuilder: (context, index) {
            final user = sharedUsers[index];
            return ListTile(
              leading: UserCircleAvatar(user: user, radius: 22),
              // pizcloud
              title: Text(displayName(user), style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(displayEmail(user), style: TextStyle(color: context.colorScheme.onSurfaceSecondary)),
              // Old behavior: always show full name/email.
              // title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w500)),
              // subtitle: Text(user.email, style: TextStyle(color: context.colorScheme.onSurfaceSecondary)),
              // #pizcloud
              trailing: userId == user.id || isOwner ? const Icon(Icons.more_horiz_rounded) : const SizedBox(),
              onTap: userId == user.id || isOwner ? () => handleUserClick(user) : null,
            );
          },
        ),
        orElse: () => const Center(child: CircularProgressIndicator()),
      );
    }

    buildSectionTitle(String text) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(text, style: context.textTheme.bodySmall),
      );
    }

    return ProviderScope(
      overrides: [currentRemoteAlbumScopedProvider.overrideWithValue(album)],
      child: PlatformScaffold(
        appBar: PlatformAppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => context.maybePop(null),
          ),
          title: Text("options".t(context: context)),
          material: (_, __) => MaterialAppBarData(centerTitle: true),
        ),
        body: ListView(
          children: [
            const SizedBox(height: 8),
            if (isOwner)
              SwitchListTile.adaptive(
                value: activityEnabled.value,
                onChanged: (bool value) async {
                  activityEnabled.value = value;
                  await ref.read(remoteAlbumProvider.notifier).setActivityStatus(album.id, value);
                },
                activeThumbColor: activityEnabled.value ? context.primaryColor : context.themeData.disabledColor,
                dense: true,
                title: Text(
                  "comments_and_likes",
                  style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
                ).t(context: context),
                subtitle: Text(
                  "let_others_respond",
                  style: context.textTheme.labelLarge?.copyWith(color: context.colorScheme.onSurfaceSecondary),
                ).t(context: context),
              ),
            buildSectionTitle("shared_album_section_people_title".t(context: context)),
            if (isOwner) ...[
              ListTile(
                leading: const Icon(Icons.person_add_rounded),
                title: Text("invite_people".t(context: context)),
                onTap: () async => addUsers(),
              ),
              const Divider(indent: 16),
            ],
            buildOwnerInfo(),
            buildSharedUsersList(),
          ],
        ),
      ),
    );
  }
}
