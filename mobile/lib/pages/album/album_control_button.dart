import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/widgets/album/album_action_filled_button.dart';

class AlbumControlButton extends ConsumerWidget {
  final void Function()? onAddPhotosPressed;
  final void Function()? onAddUsersPressed;

  const AlbumControlButton({super.key, this.onAddPhotosPressed, this.onAddUsersPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (onAddPhotosPressed != null)
            AlbumActionFilledButton(
              key: const ValueKey('add_photos_button'),
              iconData: context.platformIcon(
                material: Icons.add_photo_alternate_outlined,
                cupertino: CupertinoIcons.photo_on_rectangle,
              ),
              onPressed: onAddPhotosPressed,
              labelText: "add_photos".tr(),
            ),
          if (onAddUsersPressed != null)
            AlbumActionFilledButton(
              key: const ValueKey('add_users_button'),
              iconData: context.platformIcon(
                material: Icons.person_add_alt_rounded,
                cupertino: CupertinoIcons.person_add,
              ),
              onPressed: onAddUsersPressed,
              labelText: "album_viewer_page_share_add_users".tr(),
            ),
        ],
      ),
    );
  }
}
