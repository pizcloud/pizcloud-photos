import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

Widget platformSheetWrapper(BuildContext context, Widget child) {
  if (isCupertino(context)) {
    return CupertinoPopupSurface(
      isSurfacePainted: true,
      child: SafeArea(
        top: false,
        child: Material(
          type: MaterialType.transparency,
          child: child,
        ),
      ),
    );
  }

  return child;
}
