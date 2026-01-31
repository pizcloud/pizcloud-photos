import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/colors.dart';
import 'package:immich_mobile/providers/asset_viewer/is_motion_video_playing.provider.dart';

class MotionPhotoButton extends ConsumerWidget {
  const MotionPhotoButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(isPlayingMotionVideoProvider);

    return IconButton(
      onPressed: () {
        ref.read(isPlayingMotionVideoProvider.notifier).toggle();
      },
      icon: isPlaying
          ? Icon(
              context.platformIcon(
                material: Icons.motion_photos_pause_outlined,
                cupertino: CupertinoIcons.pause_circle,
              ),
              color: grey200,
            )
          : Icon(
              context.platformIcon(
                material: Icons.play_circle_outline_rounded,
                cupertino: CupertinoIcons.play_circle,
              ),
              color: grey200,
            ),
    );
  }
}
