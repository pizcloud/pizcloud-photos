import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

enum ToastType { info, success, error }

class ImmichToast {
  static show({
    required BuildContext context,
    required String msg,
    ToastType toastType = ToastType.info,
    ToastGravity gravity = ToastGravity.BOTTOM,
    int durationInSecond = 3,
  }) {
    final fToast = FToast();
    fToast.init(context);

    Color getColor(ToastType type, BuildContext context) => switch (type) {
      ToastType.info => context.primaryColor,
      ToastType.success => const Color.fromARGB(255, 78, 140, 124),
      ToastType.error => const Color.fromARGB(255, 220, 48, 85),
    };

    Icon getIcon(ToastType type) => switch (type) {
      ToastType.info => Icon(
        context.platformIcon(material: Icons.info_outline_rounded, cupertino: CupertinoIcons.info),
        color: context.primaryColor,
      ),
      ToastType.success => Icon(
        context.platformIcon(material: Icons.check_circle_rounded, cupertino: CupertinoIcons.check_mark_circled_solid),
        color: const Color.fromARGB(255, 78, 140, 124),
      ),
      ToastType.error => Icon(
        context.platformIcon(
          material: Icons.error_outline_rounded,
          cupertino: CupertinoIcons.exclamationmark_triangle,
        ),
        color: const Color.fromARGB(255, 240, 162, 156),
      ),
    };

    fToast.showToast(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16.0)),
          color: context.colorScheme.surfaceContainer,
          border: Border.all(color: context.colorScheme.outline.withValues(alpha: .5), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            getIcon(toastType),
            const SizedBox(width: 12.0),
            Flexible(
              child: Text(
                msg,
                style: TextStyle(color: getColor(toastType, context), fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
      positionedToastBuilder: (context, child, gravity) {
        return Positioned(
          top: gravity == ToastGravity.TOP ? 150 : null,
          bottom: gravity == ToastGravity.BOTTOM ? 150 : null,
          left: MediaQuery.of(context).size.width / 2 - 150,
          right: MediaQuery.of(context).size.width / 2 - 150,
          child: child,
        );
      },
      gravity: gravity,
      toastDuration: Duration(seconds: durationInSecond),
    );
  }
}
