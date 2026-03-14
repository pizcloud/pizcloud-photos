import 'package:flutter/material.dart';

class ViewerPageScrollPhysics extends PageScrollPhysics {
  const ViewerPageScrollPhysics({super.parent});

  // Make page snapping settle faster right after finger release.
  static const SpringDescription _fastSnapSpring = SpringDescription(
    mass: 0.9,
    stiffness: 620.0,
    damping: 45.0,
  );

  @override
  SpringDescription get spring => _fastSnapSpring;

  @override
  ViewerPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ViewerPageScrollPhysics(parent: buildParent(ancestor));
  }
}
