import 'package:flutter/widgets.dart';

RectTween mediaHeroRectTween(Rect? begin, Rect? end) {
  return RectTween(begin: begin, end: end);
}

Widget mediaHeroFlightShuttleBuilder(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final Hero fromHero = fromHeroContext.widget as Hero;
  final Hero toHero = toHeroContext.widget as Hero;
  if (flightDirection == HeroFlightDirection.push) {
    return ClipRect(child: toHero.child);
  }

  final Widget popChild = fromHero.child;
  final double startScale = _extractScale(popChild);
  if ((startScale - 1.0).abs() < 0.001) {
    return ClipRect(child: popChild);
  }

  final double targetCompensation = 1.0 / startScale;
  return AnimatedBuilder(
    animation: animation,
    child: popChild,
    builder: (context, child) {
      final double t = Curves.easeOutCubic.transform(
        animation.value.clamp(0.0, 1.0),
      );
      final double compensation = 1.0 + (targetCompensation - 1.0) * t;
      return ClipRect(
        child: Transform.scale(scale: compensation, child: child),
      );
    },
  );
}

double _extractScale(Widget widget) {
  if (widget is Transform) {
    final double value = widget.transform.getMaxScaleOnAxis();
    if (value.isFinite && value > 0) {
      return value;
    }
  }
  return 1.0;
}
