import 'package:flutter/material.dart';

class TestTabBody extends StatefulWidget {
  const TestTabBody({super.key});

  @override
  State<TestTabBody> createState() => _TestTabBodyState();
}

class _TestTabBodyState extends State<TestTabBody>
    with SingleTickerProviderStateMixin {
  static const int _columns = 5;
  static const int _itemCount = 1060;
  static const double _minScale = 1;
  static const double _maxScale = 5;
  static const Duration _snapDuration = Duration(milliseconds: 500);

  final TransformationController _controller = TransformationController();
  late final AnimationController _animationController;
  Animation<Matrix4>? _animation;
  Size? _viewportSize;
  double _startScale = 1;
  double _lastScale = 1;
  bool _didScaleThisGesture = false;
  bool _isTwoFingerGesture = false;
  double _lockedTranslationX = 0;
  Offset? _lastFocalPoint;
  bool _hasFocalPoint = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this)
      ..addListener(() {
        final animation = _animation;
        if (animation != null) {
          _controller.value = animation.value;
        }
      });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Offset _toLocal(Offset global) {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox) {
      return renderObject.globalToLocal(global);
    }
    return global;
  }

  void _snapToNearestColumn() {
    final viewport = _viewportSize;
    if (viewport == null) {
      return;
    }

    final matrix = _controller.value;
    final currentScale = matrix.getMaxScaleOnAxis();
    final columnsVisible = _columns / currentScale;
    final targetColumns = columnsVisible.round().clamp(1, _columns);
    final targetScale = (_columns / targetColumns).clamp(_minScale, _maxScale);

    final translation = matrix.getTranslation();
    final focal = _hasFocalPoint
        ? _lastFocalPoint!
        : Offset(viewport.width / 2, viewport.height / 2);
    final sceneFocalX = (focal.dx - translation.x) / currentScale;
    final sceneFocalY = (focal.dy - translation.y) / currentScale;
    var targetTranslationX = focal.dx - sceneFocalX * targetScale;
    final targetTranslationY = focal.dy - sceneFocalY * targetScale;

    final cellSize = viewport.width / _columns;
    final scaledCell = cellSize * targetScale;
    if (scaledCell > 0) {
      var leftOffset = targetTranslationX % scaledCell;
      if (leftOffset < 0) {
        leftOffset += scaledCell;
      }
      final leftShift = leftOffset <= scaledCell / 2
          ? -leftOffset
          : (scaledCell - leftOffset);

      var rightOffset = (viewport.width - targetTranslationX) % scaledCell;
      if (rightOffset < 0) {
        rightOffset += scaledCell;
      }
      final rightShift = rightOffset <= scaledCell / 2
          ? rightOffset
          : -(scaledCell - rightOffset);

      targetTranslationX +=
          leftShift.abs() <= rightShift.abs() ? leftShift : rightShift;
    }

    final targetMatrix = Matrix4.identity()
      ..translate(targetTranslationX, targetTranslationY)
      ..scale(targetScale);

    _animationController
      ..stop()
      ..reset()
      ..duration = _snapDuration;
    _animation = Matrix4Tween(begin: matrix, end: targetMatrix).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final cellSize = width / _columns;
        final rows = (_itemCount / _columns).ceil();
        final contentHeight = rows * cellSize;
        _viewportSize = Size(width, height);

        return SizedBox(
          width: width,
          height: height,
          child: ClipRect(
            child: InteractiveViewer(
              transformationController: _controller,
              minScale: _minScale,
              maxScale: _maxScale,
              constrained: false,
              alignment: Alignment.topLeft,
              onInteractionStart: (details) {
                _animationController.stop();
                _animation = null;
                _startScale = _controller.value.getMaxScaleOnAxis();
                _lastScale = _startScale;
                _didScaleThisGesture = false;
                _isTwoFingerGesture = details.pointerCount > 1;
                _lockedTranslationX = _controller.value.getTranslation().x;
                _lastFocalPoint = _toLocal(details.focalPoint);
                _hasFocalPoint = true;
              },
              onInteractionUpdate: (details) {
                final matrix = _controller.value;
                final scale = matrix.getMaxScaleOnAxis();
                final translation = matrix.getTranslation();
                _lastFocalPoint = _toLocal(details.focalPoint);
                _hasFocalPoint = true;
                _isTwoFingerGesture = details.pointerCount > 1;
                if ((scale - _lastScale).abs() > 0.001) {
                  _didScaleThisGesture = true;
                }
                _lastScale = scale;
                if (!_isTwoFingerGesture &&
                    !_didScaleThisGesture &&
                    (translation.x - _lockedTranslationX).abs() > 0.001) {
                  _controller.value = Matrix4.identity()
                    ..translate(_lockedTranslationX, translation.y)
                    ..scale(scale);
                }
              },
              onInteractionEnd: (_) {
                final endScale = _controller.value.getMaxScaleOnAxis();
                if ((endScale - _startScale).abs() > 0.001 ||
                    _didScaleThisGesture) {
                  _snapToNearestColumn();
                }
              },
              child: SizedBox(
                width: width,
                height: contentHeight,
                child: Wrap(
                  spacing: 0,
                  runSpacing: 0,
                  children: List.generate(
                    _itemCount,
                    (index) => _GridCell(
                      index: index,
                      size: cellSize,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({required this.index, required this.size});

  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.outline;

    return SizedBox(
      width: size,
      height: size,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
          ),
          child: Center(
            child: Text('${index + 1}'),
          ),
        ),
      ),
    );
  }
}
