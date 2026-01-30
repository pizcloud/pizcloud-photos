import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';

class LocalAlbumsSliverAppBar extends StatelessWidget {
  const LocalAlbumsSliverAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return PlatformSliverAppBar(
      title: Text("on_this_device".t(context: context)),
      backgroundColor: context.colorScheme.surfaceContainer,
      material: (_, __) => MaterialSliverAppBarData(
        floating: true,
        pinned: true,
        snap: false,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(5))),
        automaticallyImplyLeading: true,
        centerTitle: true,
      ),
      cupertino: (_, __) => CupertinoSliverAppBarData(
        middle: Text("on_this_device".t(context: context)),
        automaticallyImplyTitle: false,
        title: const SizedBox.shrink(),
        transitionBetweenRoutes: false,
      ),
    );
  }
}
