import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pizcloud_gallery/grid/media_hero_flight.dart';

class ViewerZoomable extends StatefulWidget {
  const ViewerZoomable({
    super.key,
    required this.heroTag,
    required this.mediaAspectRatio,
    required this.child,
    required this.onTransformStateChanged,
    required this.onGestureLockChanged,
    required this.onUnderlayRevealChanged,
    required this.onScaleChanged,
    required this.onDismissDragProgressChanged,
    required this.onDismissScaleProgressChanged,
    required this.onSingleTap,
    required this.onDismissRequested,
    required this.minScale,
    required this.maxScale,
    this.enabled = true,
  });

  final String heroTag;
  final double mediaAspectRatio;
  final Widget child;
  final ValueChanged<bool> onTransformStateChanged;
  final ValueChanged<bool> onGestureLockChanged;
  final ValueChanged<bool> onUnderlayRevealChanged;
  final ValueChanged<double> onScaleChanged;
  final ValueChanged<double> onDismissDragProgressChanged;
  final ValueChanged<double> onDismissScaleProgressChanged;
  final VoidCallback onSingleTap;
  final Future<void> Function() onDismissRequested;
  final double minScale;
  final double maxScale;
  final bool enabled;

  @override
  State<ViewerZoomable> createState() => _ViewerZoomableState();
}

class _ViewerZoomableState extends State<ViewerZoomable>
    with SingleTickerProviderStateMixin {
  static const double _scaleEpsilon = 0.1;
  static const double _startAtBaseTolerance = 0.08;
  static const double _settleDeltaEpsilon = 0.02;
  static const double _edgeSwipeTolerance = 8.0;
  static const double _edgeSwipeDragThreshold = 1.5;
  // InteractiveViewer expects a tiny drag coefficient; large values can
  // produce invalid inertia durations (Infinity/NaN).
  static const double _interactionEndFrictionCoefficient = 0.0000135;
  static const double _dragDismissStartDistance = 16.0;
  static const double _dragDismissDirectionalRatio = 1.05;
  static const Duration _settleDuration = Duration(milliseconds: 180);

  late final TransformationController _transformationController;
  late final AnimationController _settleController;
  VoidCallback? _settleListener;
  final List<Timer> _postInteractionSettleTimers = <Timer>[];
  final Set<int> _activePointers = <int>{};
  bool _isTransformed = false;
  bool _isGestureLocked = false;
  bool _isUnderlayReveal = false;
  double _gestureStartScale = 1.0;
  double? _lastScaleAtTwoFingerStart;
  bool _isVerticalDismissActive = false;
  double _verticalDismissDy = 0.0;
  Offset? _swipeStartPosition;
  Duration? _swipeStartTime;
  double _lastHorizontalDragDx = 0.0;
  double _lastDismissDragProgress = 0.0;
  double _lastDismissScaleProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _transformationController.addListener(_handleTransformChanged);
    _settleController = AnimationController(
      vsync: this,
      duration: _settleDuration,
    );
  }

  @override
  void didUpdateWidget(covariant ViewerZoomable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _isTransformed) {
      _transformationController.value = Matrix4.identity();
      _notifyTransformState(false);
    }
    if (!widget.enabled) {
      _notifyUnderlayReveal(false);
      _notifyGestureLock(false);
      _emitDismissDragProgress(0.0);
      _emitDismissScaleProgress(0.0);
    }
  }

  void _handleTransformChanged() {
    final double scale = _transformationController.value.getMaxScaleOnAxis();
    if (!scale.isFinite) {
      _transformationController.value = Matrix4.identity();
      widget.onScaleChanged(1.0);
      _emitDismissScaleProgress(0.0);
      _notifyUnderlayReveal(false);
      _notifyTransformState(false);
      return;
    }
    widget.onScaleChanged(scale);
    _emitDismissScaleProgress(_resolveDismissScaleProgress(scale));
    _updateUnderlayReveal();
    _updateGestureLockByPointerCount();
    final bool next = (scale - 1.0).abs() > _scaleEpsilon;
    if (next == _isTransformed) return;
    _notifyTransformState(next);
  }

  void _notifyTransformState(bool next) {
    _isTransformed = next;
    widget.onTransformStateChanged(next);
    if (mounted) {
      setState(() {});
    }
  }

  void _notifyGestureLock(bool next, {bool rebuild = true}) {
    if (_isGestureLocked == next) return;
    _isGestureLocked = next;
    widget.onGestureLockChanged(next);
    if (rebuild && mounted) {
      setState(() {});
    }
  }

  void _notifyUnderlayReveal(bool next) {
    if (_isUnderlayReveal == next) return;
    _isUnderlayReveal = next;
    widget.onUnderlayRevealChanged(next);
  }

  void _updateUnderlayReveal() {
    if (!widget.enabled) {
      _notifyUnderlayReveal(false);
      return;
    }
    if (_isVerticalDismissActive && _verticalDismissDy > 0) {
      _notifyUnderlayReveal(true);
      return;
    }
    final double? lastScale = _lastScaleAtTwoFingerStart;
    if (lastScale == null) {
      _notifyUnderlayReveal(false);
      return;
    }
    final double currentScale = _transformationController.value
        .getMaxScaleOnAxis();
    final bool startedAtBase = (lastScale - 1.0).abs() <= _startAtBaseTolerance;
    final bool reveal = startedAtBase && currentScale < 1.0 - _scaleEpsilon;
    _notifyUnderlayReveal(reveal);
  }

  void _updateGestureLockByPointerCount() {
    if (!widget.enabled) {
      _notifyGestureLock(false);
      return;
    }
    if (_activePointers.length >= 2) {
      _notifyGestureLock(true);
      return;
    }
    final double scale = _transformationController.value.getMaxScaleOnAxis();
    if (!scale.isFinite || scale <= 1.0 + _scaleEpsilon) {
      _notifyGestureLock(false);
      return;
    }
    final bool atHorizontalEdge = _isAtHorizontalEdge();
    if (_activePointers.isEmpty) {
      _notifyGestureLock(!atHorizontalEdge);
      return;
    }
    final bool unlockForEdgeSwipe =
        _activePointers.length == 1 &&
        (_canUnlockPageSwipeAtHorizontalEdge(_lastHorizontalDragDx) ||
            (atHorizontalEdge &&
                _lastHorizontalDragDx.abs() < _edgeSwipeDragThreshold));
    _notifyGestureLock(!unlockForEdgeSwipe);
  }

  bool _isAtHorizontalEdge() {
    final Size viewport = _resolveViewportSizeForBounds();
    if (!viewport.width.isFinite ||
        !viewport.height.isFinite ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      return false;
    }

    final Matrix4 current = _transformationController.value.clone();
    final double scale = current.getMaxScaleOnAxis();
    if (!scale.isFinite || scale <= 1.0 + _scaleEpsilon) {
      return true;
    }
    final double tx = current.storage[12];
    if (!tx.isFinite) return false;

    final double safeAspect = widget.mediaAspectRatio > 0
        ? widget.mediaAspectRatio
        : 1.0;
    final double contentWidth = viewport.width;
    final double contentHeight = viewport.width / safeAspect;
    if (!contentWidth.isFinite ||
        !contentHeight.isFinite ||
        contentWidth <= 0 ||
        contentHeight <= 0) {
      return false;
    }
    final double scaledWidth = contentWidth * scale;
    if (scaledWidth <= viewport.width + 0.5) {
      return true;
    }

    final double baseLeft = (viewport.width - contentWidth) / 2.0;
    final double minTx = viewport.width - (scale * (baseLeft + contentWidth));
    final double maxTx = -(scale * baseLeft);
    final bool atLeftEdge = tx >= maxTx - _edgeSwipeTolerance;
    final bool atRightEdge = tx <= minTx + _edgeSwipeTolerance;
    return atLeftEdge || atRightEdge;
  }

  bool _canUnlockPageSwipeAtHorizontalEdge(double dragDx) {
    if (dragDx.abs() < _edgeSwipeDragThreshold) return false;
    final Size viewport = _resolveViewportSizeForBounds();
    if (!viewport.width.isFinite ||
        !viewport.height.isFinite ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      return false;
    }

    final Matrix4 current = _transformationController.value.clone();
    final double scale = current.getMaxScaleOnAxis();
    if (!scale.isFinite || scale <= 1.0 + _scaleEpsilon) {
      return false;
    }
    final double tx = current.storage[12];
    if (!tx.isFinite) return false;

    final double safeAspect = widget.mediaAspectRatio > 0
        ? widget.mediaAspectRatio
        : 1.0;
    final double contentWidth = viewport.width;
    final double contentHeight = viewport.width / safeAspect;
    if (!contentWidth.isFinite ||
        !contentHeight.isFinite ||
        contentWidth <= 0 ||
        contentHeight <= 0) {
      return false;
    }
    final double scaledWidth = contentWidth * scale;
    if (scaledWidth <= viewport.width + 0.5) {
      return true;
    }

    final double baseLeft = (viewport.width - contentWidth) / 2.0;
    final double minTx = viewport.width - (scale * (baseLeft + contentWidth));
    final double maxTx = -(scale * baseLeft);
    final bool atLeftEdge = tx >= maxTx - _edgeSwipeTolerance;
    final bool atRightEdge = tx <= minTx + _edgeSwipeTolerance;
    if (dragDx > 0) return atLeftEdge;
    if (dragDx < 0) return atRightEdge;
    return false;
  }

  void _handleInteractionStart(ScaleStartDetails details) {
    _cancelPostInteractionSettle();
    _stopSettleAnimation();
    _gestureStartScale = _transformationController.value.getMaxScaleOnAxis();
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    if (!widget.enabled) return;
    final double endScale = _transformationController.value.getMaxScaleOnAxis();
    if (!endScale.isFinite) {
      _transformationController.value = Matrix4.identity();
      _lastScaleAtTwoFingerStart = null;
      _updateUnderlayReveal();
      return;
    }
    final double lastScale = _lastScaleAtTwoFingerStart ?? _gestureStartScale;
    final bool startedAtBase = (lastScale - 1.0).abs() <= _startAtBaseTolerance;
    final bool startedZoomed = lastScale > 1.0 + _scaleEpsilon;
    final bool releasedBelowBase = endScale < 1.0 - _scaleEpsilon;

    if (releasedBelowBase) {
      if (startedAtBase) {
        // Dismiss directly from current scale state (no forced reset to 1x).
        widget.onDismissRequested();
        return;
      } else if (startedZoomed) {
        _transformationController.value = Matrix4.identity();
      }
    } else {
      // Always settle after gesture end so pan residue is corrected reliably.
      _settleTransformedContentToViewport();
      _schedulePostInteractionSettle();
    }
    _lastScaleAtTwoFingerStart = null;
    _emitDismissScaleProgress(0.0);
    _updateUnderlayReveal();
  }

  void _handlePointerDown(PointerDownEvent event) {
    _cancelPostInteractionSettle();
    _activePointers.add(event.pointer);
    _lastHorizontalDragDx = 0.0;
    if (_activePointers.length == 1) {
      _beginSwipeDismissTracking(event);
    } else {
      _resetSwipeDismissTracking();
      _setVerticalDismiss(active: false, dy: 0.0);
    }
    if (_activePointers.length == 2) {
      _lastScaleAtTwoFingerStart = _transformationController.value
          .getMaxScaleOnAxis();
    }
    _updateGestureLockByPointerCount();
    _updateUnderlayReveal();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _lastHorizontalDragDx = event.delta.dx;
    _updateGestureLockByPointerCount();
    if (_swipeStartPosition == null || _swipeStartTime == null) return;
    if (!_canTrackSwipeDismiss()) {
      _resetSwipeDismissTracking();
      _setVerticalDismiss(active: false, dy: 0.0);
      return;
    }

    final Offset delta = event.position - _swipeStartPosition!;
    if (!_isVerticalDismissActive) {
      final bool isDownward = delta.dy > _dragDismissStartDistance;
      final bool isVertical =
          delta.dy > delta.dx.abs() * _dragDismissDirectionalRatio;
      if (isDownward && isVertical) {
        _setVerticalDismiss(active: true, dy: delta.dy);
      }
      return;
    }

    _setVerticalDismiss(active: true, dy: delta.dy);
  }

  void _handlePointerUp(PointerEvent event) {
    final bool shouldDismiss = _isVerticalDismissActive;
    _resetSwipeDismissTracking();
    _activePointers.remove(event.pointer);
    _lastHorizontalDragDx = 0.0;
    _emitDismissScaleProgress(0.0);
    _emitDismissDragProgress(0.0);
    _updateGestureLockByPointerCount();
    if (shouldDismiss) {
      widget.onDismissRequested();
      return;
    }
    _setVerticalDismiss(active: false, dy: 0.0);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _resetSwipeDismissTracking();
    _setVerticalDismiss(active: false, dy: 0.0);
    _activePointers.remove(event.pointer);
    _lastHorizontalDragDx = 0.0;
    _emitDismissScaleProgress(0.0);
    _emitDismissDragProgress(0.0);
    _updateGestureLockByPointerCount();
  }

  bool _canTrackSwipeDismiss() {
    if (!widget.enabled) return false;
    if (_activePointers.length != 1) return false;
    final double scale = _transformationController.value.getMaxScaleOnAxis();
    if (!scale.isFinite || scale > 1.5) return false;
    return _isTopEdgeInViewport();
  }

  bool _isTopEdgeInViewport() {
    final Size viewport = _resolveViewportSizeForBounds();
    if (!viewport.width.isFinite ||
        !viewport.height.isFinite ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      return false;
    }
    final Matrix4 current = _transformationController.value.clone();
    final double scale = current.getMaxScaleOnAxis();
    final double ty = current.storage[13];
    if (!scale.isFinite || scale <= 0 || !ty.isFinite) {
      return false;
    }
    final double safeAspect = widget.mediaAspectRatio > 0
        ? widget.mediaAspectRatio
        : 1.0;
    final double contentWidth = viewport.width;
    final double contentHeight = contentWidth / safeAspect;
    if (!contentHeight.isFinite || contentHeight <= 0) {
      return false;
    }
    final double baseTop = (viewport.height - contentHeight) / 2.0;
    final double topEdgeY = (scale * baseTop) + ty;
    return topEdgeY >= -_edgeSwipeTolerance &&
        topEdgeY <= viewport.height + _edgeSwipeTolerance;
  }

  void _beginSwipeDismissTracking(PointerDownEvent event) {
    if (!_canTrackSwipeDismiss()) {
      _resetSwipeDismissTracking();
      return;
    }
    _swipeStartPosition = event.position;
    _swipeStartTime = event.timeStamp;
  }

  void _resetSwipeDismissTracking() {
    _swipeStartPosition = null;
    _swipeStartTime = null;
  }

  void _setVerticalDismiss({required bool active, required double dy}) {
    final double clampedDy = dy <= 0 ? 0.0 : dy;
    final bool nextActive = active && clampedDy > 0;
    final bool sameActive = _isVerticalDismissActive == nextActive;
    final bool sameDy = (_verticalDismissDy - clampedDy).abs() < 0.1;
    if (sameActive && sameDy) {
      return;
    }
    _isVerticalDismissActive = nextActive;
    _verticalDismissDy = clampedDy;
    _emitDismissDragProgress(_resolveDismissDragProgress());
    _updateGestureLockByPointerCount();
    _updateUnderlayReveal();
    if (mounted) {
      setState(() {});
    }
  }

  void _settleTransformedContentToViewport() {
    if (!mounted) return;
    final Size viewport = _resolveViewportSizeForBounds();
    if (!viewport.width.isFinite ||
        !viewport.height.isFinite ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      return;
    }

    final Matrix4 current = _transformationController.value.clone();
    final double scale = current.getMaxScaleOnAxis();
    if (!scale.isFinite || scale <= 0) return;

    final double tx = current.storage[12];
    final double ty = current.storage[13];
    if (!tx.isFinite || !ty.isFinite) {
      _transformationController.value = Matrix4.identity();
      return;
    }

    // Near base scale: remove any residual translate/scale jitter by resetting.
    if (scale <= 1.0 + _scaleEpsilon) {
      final bool nearIdentityScale = (scale - 1.0).abs() < 0.001;
      final bool nearIdentityTranslate =
          tx.abs() < _settleDeltaEpsilon && ty.abs() < _settleDeltaEpsilon;
      if (!nearIdentityScale || !nearIdentityTranslate) {
        _animateTransformTo(Matrix4.identity());
      }
      return;
    }

    final double safeAspect = widget.mediaAspectRatio > 0
        ? widget.mediaAspectRatio
        : 1.0;
    // ViewerImageLoader uses BoxFit.fitWidth, so base width tracks viewport width.
    final double contentWidth = viewport.width;
    final double contentHeight = viewport.width / safeAspect;
    if (!contentWidth.isFinite ||
        !contentHeight.isFinite ||
        contentWidth <= 0 ||
        contentHeight <= 0) {
      return;
    }
    final double scaledWidth = contentWidth * scale;
    final double scaledHeight = contentHeight * scale;
    if (!scaledWidth.isFinite || !scaledHeight.isFinite) return;
    final double baseLeft = (viewport.width - contentWidth) / 2.0;
    final double baseTop = (viewport.height - contentHeight) / 2.0;

    double clampedTx = tx;
    if (scaledWidth > viewport.width + 0.5) {
      // Keep horizontal edges from entering viewport when content overflows.
      final double minTx = viewport.width - (scale * (baseLeft + contentWidth));
      final double maxTx = -(scale * baseLeft);
      clampedTx = tx.clamp(minTx, maxTx).toDouble();
    } else {
      // Center horizontally when content is smaller than viewport on X.
      clampedTx = ((viewport.width - scaledWidth) / 2.0) - (scale * baseLeft);
    }

    double clampedTy = ty;
    if (scaledHeight > viewport.height + 0.5) {
      // Keep vertical edges from entering viewport when content overflows.
      final double minTy =
          viewport.height - (scale * (baseTop + contentHeight));
      final double maxTy = -(scale * baseTop);
      clampedTy = ty.clamp(minTy, maxTy).toDouble();
    } else {
      // Center vertically when content is smaller than viewport on Y.
      clampedTy = ((viewport.height - scaledHeight) / 2.0) - (scale * baseTop);
    }

    if ((clampedTx - tx).abs() < _settleDeltaEpsilon &&
        (clampedTy - ty).abs() < _settleDeltaEpsilon) {
      return;
    }

    final Matrix4 target = Matrix4.identity()
      ..translateByDouble(clampedTx, clampedTy, 0.0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0);
    _animateTransformTo(target);
  }

  Size _resolveViewportSizeForBounds() {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.size;
    }
    final double mediaWidth = MediaQuery.sizeOf(context).width;
    final double mediaHeight = MediaQuery.sizeOf(context).height;
    return Size(mediaWidth, mediaHeight);
  }

  void _animateTransformTo(Matrix4 target) {
    _stopSettleAnimation();
    final Animation<Matrix4> animation =
        Matrix4Tween(
          begin: _transformationController.value.clone(),
          end: target,
        ).animate(
          CurvedAnimation(
            parent: _settleController,
            curve: Curves.easeOutCubic,
          ),
        );
    void listener() {
      _transformationController.value = animation.value;
    }

    _settleListener = listener;
    _settleController
      ..reset()
      ..addListener(listener)
      ..forward();
  }

  void _stopSettleAnimation() {
    _settleController.stop();
    final VoidCallback? listener = _settleListener;
    if (listener != null) {
      _settleController.removeListener(listener);
    }
    _settleListener = null;
  }

  void _schedulePostInteractionSettle() {
    _cancelPostInteractionSettle();
    const List<Duration> settleDelays = <Duration>[
      Duration(milliseconds: 80),
      Duration(milliseconds: 170),
      Duration(milliseconds: 280),
      Duration(milliseconds: 420),
    ];
    for (final Duration delay in settleDelays) {
      final Timer timer = Timer(delay, () {
        if (!mounted || !widget.enabled) return;
        if (_activePointers.isNotEmpty || _isVerticalDismissActive) return;
        _settleTransformedContentToViewport();
      });
      _postInteractionSettleTimers.add(timer);
    }
  }

  void _cancelPostInteractionSettle() {
    for (final Timer timer in _postInteractionSettleTimers) {
      timer.cancel();
    }
    _postInteractionSettleTimers.clear();
  }

  double _resolveDismissDragProgress() {
    if (!_isVerticalDismissActive || _verticalDismissDy <= 0) return 0.0;
    final double screenHeight = _resolveViewportHeight();
    if (!screenHeight.isFinite || screenHeight <= 0) return 0.0;
    return (_verticalDismissDy / (screenHeight * 0.8)).clamp(0.0, 1.0);
  }

  void _emitDismissDragProgress(double progress) {
    if ((_lastDismissDragProgress - progress).abs() < 0.005) return;
    _lastDismissDragProgress = progress;
    widget.onDismissDragProgressChanged(progress);
  }

  double _resolveDismissScaleProgress(double currentScale) {
    final double? lastScale = _lastScaleAtTwoFingerStart;
    if (lastScale == null) return 0.0;
    final bool startedAtBase = (lastScale - 1.0).abs() <= _startAtBaseTolerance;
    if (!startedAtBase) return 0.0;
    if (!currentScale.isFinite || currentScale >= 1.0) return 0.0;
    final double denominator = 1.0 - widget.minScale;
    if (!denominator.isFinite || denominator <= 0) return 0.0;
    return ((1.0 - currentScale) / denominator).clamp(0.0, 1.0);
  }

  void _emitDismissScaleProgress(double progress) {
    if ((_lastDismissScaleProgress - progress).abs() < 0.005) return;
    _lastDismissScaleProgress = progress;
    widget.onDismissScaleProgressChanged(progress);
  }

  double _resolveViewportHeight() {
    final Size viewport = _resolveViewportSizeForBounds();
    if (viewport.height.isFinite && viewport.height > 0) {
      return viewport.height;
    }
    return 1.0;
  }

  void _handleDoubleTap() {
    if (!widget.enabled) return;
    _cancelPostInteractionSettle();
    _stopSettleAnimation();

    final Matrix4 current = _transformationController.value.clone();
    final double currentScale = current.getMaxScaleOnAxis();
    if (!currentScale.isFinite) {
      _transformationController.value = Matrix4.identity();
      return;
    }
    if (currentScale > 1.0 + _scaleEpsilon) {
      _animateTransformTo(Matrix4.identity());
      return;
    }

    final Size viewport = _resolveViewportSizeForBounds();
    if (!viewport.width.isFinite ||
        !viewport.height.isFinite ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      return;
    }
    final double safeAspect = widget.mediaAspectRatio > 0
        ? widget.mediaAspectRatio
        : 1.0;
    final double contentWidth = viewport.width;
    final double contentHeight = contentWidth / safeAspect;
    if (!contentHeight.isFinite || contentHeight <= 0) return;

    final double fitHeightScale = viewport.height / contentHeight;
    final double targetScale = fitHeightScale.clamp(1.0, widget.maxScale);
    if ((targetScale - 1.0).abs() < 0.01) {
      _animateTransformTo(Matrix4.identity());
      return;
    }

    final double baseLeft = (viewport.width - contentWidth) / 2.0;
    final double baseTop = (viewport.height - contentHeight) / 2.0;
    final double targetTx =
        ((viewport.width - (contentWidth * targetScale)) / 2.0) -
        (targetScale * baseLeft);
    final double targetTy =
        ((viewport.height - (contentHeight * targetScale)) / 2.0) -
        (targetScale * baseTop);
    final Matrix4 target = Matrix4.identity()
      ..translateByDouble(targetTx, targetTy, 0.0, 1.0)
      ..scaleByDouble(targetScale, targetScale, 1.0, 1.0);
    _animateTransformTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = _resolveViewportHeight();
    final double progress = (_verticalDismissDy / (screenHeight * 0.8)).clamp(
      0.0,
      1.0,
    );
    final double dismissScale = 1.0 - (progress * 0.6);
    final Widget hero = Hero(
      tag: widget.heroTag,
      transitionOnUserGestures: true,
      createRectTween: mediaHeroRectTween,
      flightShuttleBuilder: mediaHeroFlightShuttleBuilder,
      child: Transform.scale(scale: dismissScale, child: widget.child),
    );
    final Widget translatedHero = Transform.translate(
      offset: Offset(0, _verticalDismissDy),
      child: hero,
    );

    if (!widget.enabled) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onSingleTap,
        child: translatedHero,
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onSingleTap,
        onDoubleTap: _handleDoubleTap,
        child: ClipRect(
          child: InteractiveViewer(
            transformationController: _transformationController,
            scaleEnabled: true,
            panEnabled: _isGestureLocked,
            interactionEndFrictionCoefficient:
                _interactionEndFrictionCoefficient,
            minScale: widget.minScale,
            maxScale: widget.maxScale,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            clipBehavior: Clip.none,
            onInteractionStart: _handleInteractionStart,
            onInteractionEnd: _handleInteractionEnd,
            child: translatedHero,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cancelPostInteractionSettle();
    _stopSettleAnimation();
    _emitDismissScaleProgress(0.0);
    _emitDismissDragProgress(0.0);
    _settleController.dispose();
    _notifyGestureLock(false, rebuild: false);
    _notifyUnderlayReveal(false);
    _activePointers.clear();
    _transformationController.removeListener(_handleTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }
}
