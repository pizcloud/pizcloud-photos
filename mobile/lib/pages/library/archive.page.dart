import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/multiselect.provider.dart';
import 'package:immich_mobile/providers/timeline.provider.dart';
import 'package:immich_mobile/widgets/asset_grid/multiselect_grid.dart';

@RoutePage()
class ArchivePage extends HookConsumerWidget {
  const ArchivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    PlatformAppBar buildAppBar() {
      final archiveRenderList = ref.watch(archiveTimelineProvider);
      final count = archiveRenderList.value?.totalAssets.toString() ?? "?";
      return PlatformAppBar(
        leading: IconButton(onPressed: () => context.maybePop(), icon: Icon(context.platformIcons.back)),
        automaticallyImplyLeading: false,
        title: const Text('archive_page_title').tr(namedArgs: {'count': count}),
        material: (_, __) => MaterialAppBarData(centerTitle: true),
      );
    }

    return PlatformScaffold(
      appBar: ref.watch(multiselectProvider) ? null : buildAppBar(),
      body: MultiselectGrid(
        renderListProvider: archiveTimelineProvider,
        unarchive: true,
        archiveEnabled: true,
        deleteEnabled: true,
        editEnabled: true,
      ),
    );
  }
}
