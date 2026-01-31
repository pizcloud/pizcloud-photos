import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/timeline.provider.dart';
import 'package:immich_mobile/widgets/asset_grid/multiselect_grid.dart';

@RoutePage()
class AllVideosPage extends HookConsumerWidget {
  const AllVideosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('videos').tr(),
        leading: IconButton(onPressed: () => context.maybePop(), icon: Icon(context.platformIcons.back)),
      ),
      body: MultiselectGrid(renderListProvider: allVideosTimelineProvider),
    );
  }
}
