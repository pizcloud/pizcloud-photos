import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:immich_mobile/utils/platform_sheet.dart';

Future<T> showFilterBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  bool isScrollControlled = false,
  bool isDismissible = true,
}) async {
  return await showPlatformModalSheet(
    context: context,
    material: MaterialModalSheetData(
      isScrollControlled: isScrollControlled,
      useSafeArea: false,
      isDismissible: isDismissible,
      showDragHandle: isDismissible,
    ),
    builder: (BuildContext context) {
      return platformSheetWrapper(context, child);
    },
  );
}
