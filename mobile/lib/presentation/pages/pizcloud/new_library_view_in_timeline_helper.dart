import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/presentation/pages/pizcloud/new_library_media_mapper.dart';
import 'package:immich_mobile/providers/pizcloud/new_library.provider.dart';
import 'package:immich_mobile/providers/tab.provider.dart';
import 'package:immich_mobile/routing/router.dart';

Future<void> focusNewLibraryAndLocateAsset({
  required BuildContext context,
  required WidgetRef ref,
  required BaseAsset asset,
}) async {
  final String? mediaItemId = buildNewLibraryMediaItemId(asset);
  if (mediaItemId == null) {
    return;
  }

  final appRouter = ref.read(appRouterProvider);
  final locateNotifier = ref.read(newLibraryLocateRequestProvider.notifier);
  final tabNotifier = ref.read(tabProvider.notifier);

  await context.maybePop();
  await WidgetsBinding.instance.endOfFrame;

  await appRouter.navigate(const TabShellRoute(children: [NewLibraryRoute()]));
  await WidgetsBinding.instance.endOfFrame;
  tabNotifier.state = TabEnum.newLibrary;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    locateNotifier.queueMediaItemId(mediaItemId);
  });
}
