import 'dart:math';

import 'package:flutter/widgets.dart';

import 'grid_state.dart';

class GridGestureController {
  final GridState grid;
  final ValueNotifier<bool> scalingLock;
  final Future<void> Function() onScaleEnd;
  final VoidCallback? onDebugTripleTouch;

  final Map<int, Offset> _pointers = <int, Offset>{};
  Offset? _lastFocal;

  GridGestureController({
    required this.grid,
    required this.scalingLock,
    required this.onScaleEnd,
    this.onDebugTripleTouch,
  });

  void onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    grid.pointerCount++;
    scalingLock.value = grid.pointerCount >= 2;
    if (grid.pointerCount == 2) {
      grid.beginScaleDirectionTracking();
      _updateFocalPoint();
      final Offset? focal = _lastFocal;
      if (focal != null) {
        grid.updateFocusCell(focal, alreadyScene: true);
      }
    } else if (grid.pointerCount == 3) {
      onDebugTripleTouch?.call();
    }
  }

  void onPointerMove(PointerMoveEvent event) {
    if (_pointers.containsKey(event.pointer)) {
      _pointers[event.pointer] = event.localPosition;
    }
  }

  Future<void> onPointerUp(PointerUpEvent event) async {
    _pointers.remove(event.pointer);
    final int prevCount = grid.pointerCount;
    grid.pointerCount = max(0, grid.pointerCount - 1);
    scalingLock.value = grid.pointerCount >= 2;
    if (prevCount >= 2 && grid.pointerCount < 2) {
      grid.endScaleDirectionTracking();
      await onScaleEnd();
    }
  }

  void onPointerCancel() {
    grid.pointerCount = 0;
    scalingLock.value = false;
    grid.resetScaleDirection();
    _pointers.clear();
    _lastFocal = null;
  }

  void onInteractionUpdate(ScaleUpdateDetails details) {
    // Keep current behavior: no-op in gallery.
  }

  void dispose() {
    _pointers.clear();
    _lastFocal = null;
  }

  Offset _toScene(Offset viewportOffset) {
    final List<double> m = grid.transformController.value.storage;
    final double scale = m[0];
    final double tx = m[12];
    final double ty = m[13];
    if (scale == 0) return viewportOffset;
    return Offset(
      (viewportOffset.dx - tx) / scale,
      (viewportOffset.dy - ty) / scale,
    );
  }

  void _updateFocalPoint() {
    if (_pointers.length < 2) return;
    Offset sum = Offset.zero;
    for (final Offset p in _pointers.values) {
      sum += p;
    }
    final Offset avg = sum / _pointers.length.toDouble();
    _lastFocal = _toScene(avg);
  }
}
