import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'grid_state.dart';

// new
typedef RealDataScrollbarOverlayBuilder =
    Widget? Function(
      BuildContext context,
      RealDataScrollbarOverlayMetrics metrics,
    );

@immutable
class RealDataScrollbarOverlayMetrics {
  const RealDataScrollbarOverlayMetrics({
    required this.width,
    required this.trackExtent,
    required this.thumbTop,
    required this.thumbExtent,
    required this.canScroll,
  });

  final double width;
  final double trackExtent;
  final double thumbTop;
  final double thumbExtent;
  final bool canScroll;

  double get thumbCenterY => thumbTop + (thumbExtent / 2);
}
// #new

class RealDataScrollbar extends StatefulWidget {
  const RealDataScrollbar({
    super.key,
    required this.grid,
    required this.viewportHeight,
    this.interactive = true,
    this.enableTrackGestures = true,
    this.onDragStateChanged,
    this.width = 56,
    this.thumbDiameter = 48,
    this.showTrack = false,
    this.margin = const EdgeInsets.symmetric(vertical: 8),
    this.overlayBuilder, // new
  });

  final GridState grid;
  final double viewportHeight;
  final bool interactive;
  final bool enableTrackGestures;
  final ValueChanged<bool>? onDragStateChanged;
  final double width;
  final double thumbDiameter;
  final bool showTrack;
  final EdgeInsets margin;
  final RealDataScrollbarOverlayBuilder? overlayBuilder; // new

  @override
  State<RealDataScrollbar> createState() => _RealDataScrollbarState();
}

class _RealDataScrollbarState extends State<RealDataScrollbar> {
  static const double _minThumbTouchExtent = 88;
  double? _thumbDragGrabOffset;
  bool _isDragging = false;
  int? _activeThumbPointer;
  int? _activeTrackPointer;
  double? _pendingTrackY;
  double? _pendingDragGrabOffset;
  _RealScrollbarMetrics? _pendingMetrics;
  bool _jumpQueued = false;

  @override
  void dispose() {
    _setDragging(false);
    _pendingTrackY = null;
    _pendingDragGrabOffset = null;
    _pendingMetrics = null;
    _activeThumbPointer = null;
    _activeTrackPointer = null;
    _jumpQueued = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.grid.scrollOffset,
        widget.grid.transformController,
      ]),
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final double trackExtent = math.max(
              0,
              constraints.maxHeight - widget.margin.vertical,
            );
            if (trackExtent <= 0) {
              return const SizedBox.shrink();
            }

            final _RealScrollbarMetrics metrics =
                _RealScrollbarMetrics.fromGrid(
                  grid: widget.grid,
                  trackExtent: trackExtent,
                  viewportHeight: widget.viewportHeight,
                  thumbExtent: widget.thumbDiameter,
                );
            final ColorScheme scheme = Theme.of(context).colorScheme;
            final Color thumbIconColor = metrics.canScroll
                ? Colors.white
                : Colors.white54;
            final BorderRadius radius = BorderRadius.circular(widget.width / 2);
            final bool canHandleThumbGesture =
                widget.interactive && metrics.canScroll;
            final bool canHandleTrackGesture =
                widget.interactive &&
                widget.enableTrackGestures &&
                metrics.canScroll;
            final double thumbTouchExtent = math.max(
              metrics.thumbExtent,
              _minThumbTouchExtent,
            );
            // new
            final RealDataScrollbarOverlayMetrics overlayMetrics =
                RealDataScrollbarOverlayMetrics(
                  width: widget.width,
                  trackExtent: trackExtent,
                  thumbTop: metrics.thumbTop,
                  thumbExtent: metrics.thumbExtent,
                  canScroll: metrics.canScroll,
                );
            final Widget? overlay = widget.overlayBuilder?.call(
              context,
              overlayMetrics,
            );
            // #new

            final Widget track = SizedBox(
              width: widget.width,
              height: trackExtent,
              child: Stack(
                clipBehavior: Clip.none, // new
                children: <Widget>[
                  if (widget.showTrack)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.outlineVariant.withAlpha(80),
                          borderRadius: radius,
                        ),
                      ),
                    ),
                  Builder(
                    builder: (context) {
                      final double touchExtent = thumbTouchExtent;
                      final double touchInset =
                          (touchExtent - metrics.thumbExtent) / 2;
                      return Positioned(
                        left: (widget.width - touchExtent) / 2,
                        top: metrics.thumbTop - touchInset,
                        child: SizedBox(
                          width: touchExtent,
                          height: touchExtent,
                          child: Center(
                            child: SizedBox(
                              width: metrics.thumbExtent,
                              height: metrics.thumbExtent,
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                size: metrics.thumbExtent * 0.72,
                                color: thumbIconColor,
                                shadows: const <Shadow>[
                                  Shadow(
                                    color: Color(0xCC000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (overlay != null) ...<Widget>[overlay], // new
                ],
              ),
            );

            final Widget content = Listener(
              behavior: canHandleTrackGesture
                  ? HitTestBehavior.opaque
                  : HitTestBehavior.deferToChild,
              onPointerDown: (event) {
                if (!widget.interactive || !metrics.canScroll) {
                  return;
                }
                final bool onThumb = _isInsideThumb(
                  event.localPosition,
                  metrics,
                  touchExtent: thumbTouchExtent,
                );
                if (onThumb && canHandleThumbGesture) {
                  _activeThumbPointer = event.pointer;
                  _activeTrackPointer = null;
                  _setDragging(true);
                  _thumbDragGrabOffset =
                      (event.localPosition.dy - metrics.thumbTop).clamp(
                        0.0,
                        metrics.thumbExtent,
                      );
                  _applyJumpToTrackPosition(
                    event.localPosition.dy,
                    metrics,
                    dragGrabOffset: _thumbDragGrabOffset,
                  );
                  return;
                }
                if (!onThumb && canHandleTrackGesture) {
                  _activeTrackPointer = event.pointer;
                  _activeThumbPointer = null;
                  _setDragging(true);
                  _applyJumpToTrackPosition(event.localPosition.dy, metrics);
                }
              },
              onPointerMove: (event) {
                if (_activeThumbPointer == event.pointer) {
                  _applyJumpToTrackPosition(
                    event.localPosition.dy,
                    metrics,
                    dragGrabOffset: _thumbDragGrabOffset,
                  );
                  return;
                }
                if (_activeTrackPointer == event.pointer) {
                  _queueJumpToTrackPosition(event.localPosition.dy, metrics);
                }
              },
              onPointerUp: (event) {
                if (_activeThumbPointer == event.pointer) {
                  _activeThumbPointer = null;
                  _thumbDragGrabOffset = null;
                }
                if (_activeTrackPointer == event.pointer) {
                  _activeTrackPointer = null;
                }
                if (_activeThumbPointer == null &&
                    _activeTrackPointer == null) {
                  _setDragging(false);
                }
              },
              onPointerCancel: (event) {
                if (_activeThumbPointer == event.pointer) {
                  _activeThumbPointer = null;
                  _thumbDragGrabOffset = null;
                }
                if (_activeTrackPointer == event.pointer) {
                  _activeTrackPointer = null;
                }
                if (_activeThumbPointer == null &&
                    _activeTrackPointer == null) {
                  _setDragging(false);
                }
              },
              child: track,
            );

            return Padding(padding: widget.margin, child: content);
          },
        );
      },
    );
  }

  void _queueJumpToTrackPosition(
    double trackY,
    _RealScrollbarMetrics metrics, {
    double? dragGrabOffset,
  }) {
    _pendingTrackY = trackY;
    _pendingMetrics = metrics;
    _pendingDragGrabOffset = dragGrabOffset;
    if (_jumpQueued) {
      return;
    }
    _jumpQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpQueued = false;
      if (!mounted) {
        return;
      }
      final _RealScrollbarMetrics? pendingMetrics = _pendingMetrics;
      final double? pendingTrackY = _pendingTrackY;
      if (pendingMetrics == null || pendingTrackY == null) {
        return;
      }
      final double? pendingGrabOffset = _pendingDragGrabOffset;
      _pendingMetrics = null;
      _pendingTrackY = null;
      _pendingDragGrabOffset = null;
      _applyJumpToTrackPosition(
        pendingTrackY,
        pendingMetrics,
        dragGrabOffset: pendingGrabOffset,
      );
    });
  }

  void _applyJumpToTrackPosition(
    double trackY,
    _RealScrollbarMetrics metrics, {
    double? dragGrabOffset,
  }) {
    final double clampedTrackY = trackY.clamp(0.0, metrics.trackExtent);
    final double thumbAnchor = dragGrabOffset ?? (metrics.thumbExtent / 2);
    final double targetThumbTop = (clampedTrackY - thumbAnchor).clamp(
      0.0,
      metrics.maxThumbTravel,
    );
    final double normalized = metrics.maxThumbTravel <= 0
        ? 0
        : (targetThumbTop / metrics.maxThumbTravel).clamp(0.0, 1.0);
    final double targetRealTopRow = normalized * metrics.maxTopRow;
    if ((targetRealTopRow - metrics.currentTopRow).abs() < 0.15) {
      return;
    }
    widget.grid.jumpToRealTopRow(targetRealTopRow, colCount: metrics.colCount);
  }

  void _setDragging(bool dragging) {
    if (_isDragging == dragging) return;
    _isDragging = dragging;
    widget.onDragStateChanged?.call(dragging);
  }

  bool _isInsideThumb(
    Offset localPosition,
    _RealScrollbarMetrics metrics, {
    required double touchExtent,
  }) {
    final double thumbLeft = (widget.width - touchExtent) / 2;
    final double touchInset = (touchExtent - metrics.thumbExtent) / 2;
    final Rect thumbRect = Rect.fromLTWH(
      thumbLeft,
      metrics.thumbTop - touchInset,
      touchExtent,
      touchExtent,
    );
    return thumbRect.contains(localPosition);
  }
}

class _RealScrollbarMetrics {
  const _RealScrollbarMetrics({
    required this.colCount,
    required this.trackExtent,
    required this.thumbExtent,
    required this.thumbTop,
    required this.maxThumbTravel,
    required this.maxTopRow,
    required this.currentTopRow,
    required this.canScroll,
  });

  final int colCount;
  final double trackExtent;
  final double thumbExtent;
  final double thumbTop;
  final double maxThumbTravel;
  final double maxTopRow;
  final double currentTopRow;
  final bool canScroll;

  factory _RealScrollbarMetrics.fromGrid({
    required GridState grid,
    required double trackExtent,
    required double viewportHeight,
    required double thumbExtent,
  }) {
    final int colCount = math.max(1, grid.currentColCount);
    final int totalRows = math.max(
      0,
      grid.realDataRowCount(colCount: colCount),
    );

    final double visibleRows = grid.visibleDataRowsInViewport(viewportHeight);
    final double maxTopRow = math.max(0, totalRows - visibleRows);
    final double rawTopRow = grid.currentRealTopRow(colCount: colCount);
    final double topRow = rawTopRow.isFinite
        ? rawTopRow.clamp(0.0, maxTopRow).toDouble()
        : 0.0;

    final double resolvedThumbExtent = thumbExtent
        .clamp(0.0, trackExtent)
        .toDouble();
    final double maxThumbTravel = math.max(
      0,
      trackExtent - resolvedThumbExtent,
    );
    final double normalized = maxTopRow <= 0 ? 0 : (topRow / maxTopRow);
    final double thumbTop = (normalized * maxThumbTravel).clamp(
      0.0,
      maxThumbTravel,
    );

    return _RealScrollbarMetrics(
      colCount: colCount,
      trackExtent: trackExtent,
      thumbExtent: resolvedThumbExtent,
      thumbTop: thumbTop,
      maxThumbTravel: maxThumbTravel,
      maxTopRow: maxTopRow,
      currentTopRow: topRow,
      canScroll: maxTopRow > 0 && maxThumbTravel > 0,
    );
  }
}
