import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/multiselect.provider.dart';
import 'package:immich_mobile/providers/timeline.provider.dart';
import 'package:immich_mobile/widgets/asset_grid/multiselect_grid.dart';

@RoutePage()
class FavoritesPage extends HookConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    PlatformAppBar buildAppBar() {
      return PlatformAppBar(
        leading: IconButton(onPressed: () => context.maybePop(), icon: const Icon(Icons.arrow_back_ios_rounded)),
        automaticallyImplyLeading: false,
        title: const Text('favorites').tr(),
        material: (_, __) => MaterialAppBarData(centerTitle: true),
      );
    }

    return PlatformScaffold(
      appBar: ref.watch(multiselectProvider) ? null : buildAppBar(),
      body: MultiselectGrid(
        renderListProvider: favoriteTimelineProvider,
        favoriteEnabled: true,
        editEnabled: true,
        unfavorite: true,
      ),
    );
  }
}
