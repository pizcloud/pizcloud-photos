import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/search/people.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/widgets/search/person_name_edit_form.dart';
import 'package:immich_mobile/widgets/asset_grid/multiselect_grid.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';
import 'package:immich_mobile/utils/platform_sheet.dart';

@RoutePage()
class PersonResultPage extends HookConsumerWidget {
  final String personId;
  final String personName;

  const PersonResultPage({super.key, required this.personId, required this.personName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = useState(personName);

    showEditNameDialog() {
      showPlatformDialog(
        context: context,
        useRootNavigator: false,
        builder: (BuildContext context) {
          return PersonNameEditForm(personId: personId, personName: name.value);
        },
      ).then((result) {
        if (result != null && result.success) {
          name.value = result.updatedName;
        }
      });
    }

    void buildBottomSheet() {
      showPlatformModalSheet(
        context: context,
        material: MaterialModalSheetData(
          backgroundColor: context.scaffoldBackgroundColor,
          isScrollControlled: false,
          useSafeArea: true,
        ),
        builder: (context) {
          return platformSheetWrapper(
            context,
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(context.platformIcon(material: Icons.edit_outlined, cupertino: CupertinoIcons.pencil)),
                  title: const Text('edit_name', style: TextStyle(fontWeight: FontWeight.bold)).tr(),
                  onTap: showEditNameDialog,
                ),
              ],
            ),
          );
        },
      );
    }

    buildTitleBlock() {
      return GestureDetector(
        onTap: showEditNameDialog,
        child: name.value.isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('add_a_name', style: context.textTheme.titleMedium?.copyWith(color: context.primaryColor)).tr(),
                  Text('find_them_fast', style: context.textTheme.labelLarge).tr(),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(name.value, style: context.textTheme.titleLarge, overflow: TextOverflow.ellipsis)],
              ),
      );
    }

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text(name.value),
        leading: IconButton(onPressed: () => context.maybePop(), icon: Icon(context.platformIcons.back)),
        trailingActions: [
          IconButton(
            onPressed: buildBottomSheet,
            icon: Icon(context.platformIcon(material: Icons.more_vert_rounded, cupertino: CupertinoIcons.ellipsis)),
          ),
        ],
      ),
      body: MultiselectGrid(
        renderListProvider: personAssetsProvider(personId),
        topWidget: Padding(
          padding: const EdgeInsets.only(left: 8.0, top: 24),
          child: Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: NetworkImage(getFaceThumbnailUrl(personId), headers: ApiService.getRequestHeaders()),
              ),
              Expanded(
                child: Padding(padding: const EdgeInsets.only(left: 16.0, right: 16.0), child: buildTitleBlock()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
