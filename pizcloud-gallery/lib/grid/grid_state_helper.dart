import 'package:flutter/material.dart';

class ScaleDecision {
  final int colCount;
  final double snapScale;

  const ScaleDecision({
    required this.colCount,
    required this.snapScale,
  });
}

class GridStateHelper {
  static const double minScale = 0.0001;
  static const double maxScale = 1000.0;
  static const double scaleFor5Cols = 1.0;
  static const double scaleFor3Cols = 1.6666;
  static const double scaleFor1Col = 5.0;

  // Directional hysteresis:
  // - scale up: switch earlier to denser zoom (fewer cols)
  // - scale down: switch earlier to wider zoom (more cols)
  static const double upRatio = 0.08;
  static const double downRatio = 0.08;

  static bool isValidCellSize(double cellSize) {
    return cellSize > 0 && !cellSize.isNaN && !cellSize.isInfinite;
  }

  static bool isValidViewport(Size viewport) {
    return !viewport.isEmpty &&
        viewport.width.isFinite &&
        viewport.height.isFinite;
  }

  static double safeScale(Matrix4 matrix) {
    return matrix.getMaxScaleOnAxis().clamp(minScale, maxScale);
  }

  static double translateX(Matrix4 matrix) {
    return matrix.storage[12];
  }

  static double translateY(Matrix4 matrix) {
    return matrix.storage[13];
  }

  static double topContentY({
    required double scrollY,
    required double translateY,
    required double scale,
  }) {
    return scrollY - (translateY / scale);
  }

  static double targetScrollYForBaseTop({
    required double baseTopY,
    required double translateY,
    required double scale,
  }) {
    return baseTopY + (translateY / scale);
  }

  static double clampToScrollExtents({
    required double value,
    required ScrollPosition position,
  }) {
    return value
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  static ScaleDecision resolveScaleDecision({
    required double scale,
    required int currentColCount,
    required int scaleDirection,
  }) {
    final int current = currentColCount.clamp(1, 5);
    final double upFrom5 = scaleFor5Cols * (1 + upRatio);
    final double upFrom3 = scaleFor3Cols * (1 + 0.3);
    final double downFrom3 = scaleFor3Cols * (1 - downRatio);
    final double downFrom1 = scaleFor1Col * (1 - downRatio);

    int next = current;

    if (scaleDirection > 0) {
      // Zooming in: move step-by-step to fewer columns sooner.
      if (current == 5 && scale >= upFrom5) {
        next = 3;
      } else if (current == 3 && scale >= upFrom3) {
        next = 1;
      }
    } else if (scaleDirection < 0) {
      // Zooming out: move step-by-step to more columns sooner.
      if (current == 1 && scale <= downFrom1) {
        next = 3;
      } else if (current == 3 && scale <= downFrom3) {
        next = 5;
      }
    } else {
      // Unknown direction: keep current layout to avoid jumpy switching.
      next = current;
    }

    final double snapScale = next == 5
        ? scaleFor5Cols
        : (next == 3 ? scaleFor3Cols : scaleFor1Col);
    return ScaleDecision(colCount: next, snapScale: snapScale);
  }
}
