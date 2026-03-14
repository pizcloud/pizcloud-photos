import 'package:flutter/widgets.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

bool isCupertino(BuildContext context) {
  final target = platform(context);
  return target == PlatformTarget.iOS || target == PlatformTarget.macOS;
}
