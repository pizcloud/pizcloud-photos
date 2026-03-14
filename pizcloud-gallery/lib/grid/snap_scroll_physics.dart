import 'package:flutter/widgets.dart';

class SnapScrollPhysics extends ClampingScrollPhysics {
  const SnapScrollPhysics({
    this.lockTopOffset = 0.0,
    this.lockBottomOffset = 0.0,
    this.lockOffsetsResolver,
    this.maxOverScroll = 200.0,
    this.stiffness = 500.0,
    this.damping = 30.0,
    this.mass = 1.0,
    super.parent,
  });

  final double lockTopOffset;
  final double lockBottomOffset;
  final ({double lockTopOffset, double lockBottomOffset}) Function()?
  lockOffsetsResolver;
  final double maxOverScroll;
  final double stiffness;
  final double damping;
  final double mass;

  @override
  SnapScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return SnapScrollPhysics(
      lockTopOffset: lockTopOffset,
      lockBottomOffset: lockBottomOffset,
      lockOffsetsResolver: lockOffsetsResolver,
      maxOverScroll: maxOverScroll,
      stiffness: stiffness,
      damping: damping,
      mass: mass,
      parent: buildParent(ancestor),
    );
  }

  @override
  SpringDescription get spring =>
      SpringDescription(mass: mass, stiffness: stiffness, damping: damping);

  ({double top, double bottom}) _resolveLocks(ScrollMetrics position) {
    final ({double lockTopOffset, double lockBottomOffset})? dynamicLocks =
        lockOffsetsResolver?.call();
    final double minExtent = position.minScrollExtent;
    final double maxExtent = position.maxScrollExtent;
    final double top = (dynamicLocks?.lockTopOffset ?? lockTopOffset)
        .clamp(minExtent, maxExtent)
        .toDouble();
    final double bottom = (dynamicLocks?.lockBottomOffset ?? lockBottomOffset)
        .clamp(minExtent, maxExtent)
        .toDouble();
    return (top: top, bottom: bottom < top ? top : bottom);
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final ({double top, double bottom}) locks = _resolveLocks(position);
    final double over = maxOverScroll < 0 ? 0 : maxOverScroll;
    final double topLimit = locks.top - over;
    final double bottomLimit = locks.bottom + over;

    if (value < topLimit) {
      return value - topLimit;
    }
    if (value > bottomLimit) {
      return value - bottomLimit;
    }
    return super.applyBoundaryConditions(position, value);
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final ({double top, double bottom}) locks = _resolveLocks(position);
    final double over = maxOverScroll <= 0 ? 1.0 : maxOverScroll;
    final double pixels = position.pixels;

    final bool isOverTop = pixels < locks.top;
    final bool isOverBottom = pixels > locks.bottom;
    if (!isOverTop && !isOverBottom) {
      return super.applyPhysicsToUserOffset(position, offset);
    }

    final double overscrollAmount = isOverTop
        ? (locks.top - pixels)
        : (pixels - locks.bottom);
    final double t = (overscrollAmount / over).clamp(0.0, 1.0);
    final double resistance = 1 / (1 + 4 * t);
    return offset * resistance;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final ({double top, double bottom}) locks = _resolveLocks(position);
    final double top = locks.top;
    final double bottom = locks.bottom;
    final double pixels = position.pixels;

    final Tolerance tol = toleranceFor(position);
    final bool shouldSnapTop = pixels < top - tol.distance;
    final bool shouldSnapBottom = pixels > bottom + tol.distance;
    if (shouldSnapTop || shouldSnapBottom) {
      final double target = shouldSnapTop ? top : bottom;
      return ScrollSpringSimulation(
        spring,
        pixels,
        target,
        velocity,
        tolerance: tol,
      );
    }

    return super.createBallisticSimulation(position, velocity);
  }
}
