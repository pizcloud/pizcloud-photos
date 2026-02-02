import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';

class SelectionSliverAppBar extends ConsumerStatefulWidget {
  const SelectionSliverAppBar({super.key});

  @override
  ConsumerState<SelectionSliverAppBar> createState() => _SelectionSliverAppBarState();
}

class _SelectionSliverAppBarState extends ConsumerState<SelectionSliverAppBar> {
  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(multiSelectProvider.select((s) => s.selectedAssets));

    final toExclude = ref.watch(multiSelectProvider.select((s) => s.lockedSelectionAssets));

    final filteredAssets = selection.where((asset) {
      return !toExclude.contains(asset);
    }).toSet();

    onDone(Set<BaseAsset> selected) {
      ref.read(multiSelectProvider.notifier).reset();
      context.pop<Set<BaseAsset>>(selected);
    }

    final titleWidget = Text("Select {count}".t(context: context, args: {'count': filteredAssets.length.toString()}));
    final doneButtonMaterial = TextButton(
      onPressed: () => onDone(filteredAssets),
      child: Text(
        'done'.t(context: context),
        style: context.textTheme.titleSmall?.copyWith(color: context.colorScheme.primary),
      ),
    );

    final doneButtonCupertino = CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      minimumSize: Size.zero,
      onPressed: () => onDone(filteredAssets),
      child: Text(
        'done'.t(context: context),
        style: TextStyle(
          color: context.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    // iOS: avoid large-title duplication by keeping the PlatformSliverAppBar title null.
    return PlatformSliverAppBar(
      backgroundColor: context.colorScheme.surfaceContainer,
      leading: IconButton(
        icon: Icon(context.platformIcons.clear),
        onPressed: () {
          ref.read(multiSelectProvider.notifier).reset();
          context.pop<Set<BaseAsset>>(null);
        },
      ),
      title: isCupertino(context) ? null : titleWidget,
      material: (_, __) => MaterialSliverAppBarData(
        floating: true,
        pinned: true,
        snap: false,
        centerTitle: true,
        title: titleWidget,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(5))),
        actions: [doneButtonMaterial],
      ),
      cupertino: (_, __) => CupertinoSliverAppBarData(
        automaticallyImplyTitle: false,
        title: const SizedBox.shrink(),
        middle: titleWidget,
        alwaysShowMiddle: true,
        transitionBetweenRoutes: false,
        trailing: doneButtonCupertino,
      ),
    );
  }
}
