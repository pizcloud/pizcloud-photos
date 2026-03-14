import 'package:flutter/material.dart';

class PizGallery extends StatefulWidget {
  const PizGallery({super.key});

  @override
  State<PizGallery> createState() => _PizGalleryState();
}

class _PizGalleryState extends State<PizGallery>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 60;
  static const double _scale3Item = 1.6666;
  final _PizGalleryScrollController _controller = _PizGalleryScrollController();
  final GlobalKey _gridBoxKey = GlobalKey();
  final GlobalKey _gridViewKey = GlobalKey();
  int _itemCount = _pageSize;
  double _scale = 1.0;
  double _baseScale = 1.0;
  bool _isScalingUp = false;
  int _pointerCount = 0;
  bool _isScaling = false;
  int _cols = 5;
  Alignment _scaleAlignment = Alignment.center;
  bool _setScaleAlignment = false;
  late final AnimationController _scaleController;
  Animation<double>? _scaleAnimation;
  Offset _scaleOrigin = Offset(0, 0);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        final nextValue = _scaleAnimation?.value;
        if (nextValue != null) {
          setState(() {
            _scale = nextValue;
            _updateScrollExtents();
          });
        }
      });
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    // debugPrint('_onScroll position: $position.toString()');
    if (position.pixels >= position.maxScrollExtent - 200) {
      setState(() {
        _itemCount += _pageSize;
      });
    }
  }

  Alignment _alignmentForPoint(Offset local, Size size) {
    final thirdWidth = size.width / 3;
    final thirdHeight = size.height / 3;
    final column = local.dx < thirdWidth
        ? 0
        : (local.dx < thirdWidth * 2 ? 1 : 2);
    final row = local.dy < thirdHeight
        ? 0
        : (local.dy < thirdHeight * 2 ? 1 : 2);

    if (row == 0 && column == 0) return Alignment.topLeft;
    if (row == 0 && column == 1) return Alignment.topCenter;
    if (row == 0 && column == 2) return Alignment.topRight;
    if (row == 1 && column == 0) return Alignment.centerLeft;
    if (row == 1 && column == 1) return Alignment.center;
    if (row == 1 && column == 2) return Alignment.centerRight;
    if (row == 2 && column == 0) return Alignment.bottomLeft;
    if (row == 2 && column == 1) return Alignment.bottomCenter;
    return Alignment.bottomRight;
  }

  void _updateScrollExtents() {
    if (!_controller.hasClients) return;
    final gridBox = _gridViewKey.currentContext?.findRenderObject();
    final renderBox = gridBox is RenderBox
        ? gridBox
        : _gridBoxKey.currentContext?.findRenderObject();
    if (renderBox is! RenderBox) return;
    final rawOverflow =
        (renderBox.size.height * (_scale - 1)).clamp(0.0, double.infinity);
    final overflow = rawOverflow / _scale;
    final topFactor = (_scaleAlignment.y + 1) / 2;
    _controller.extraLeadingExtent = overflow * topFactor;
    _controller.extraTrailingExtent = overflow - _controller.extraLeadingExtent;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).dividerColor;
    return SizedBox(
      // height: 10000,
      key: _gridBoxKey,
      child: Listener(
        onPointerDown: (_) {
          _pointerCount += 1;
          if (_pointerCount > 1 && !_isScaling) {
            setState(() {
              _isScaling = true;
            });
          }
        },
        onPointerUp: (_) {
          _pointerCount = (_pointerCount - 1).clamp(0, 10);
          if (_pointerCount < 2 && _isScaling) {
            setState(() {
              _isScaling = false;
            });
          }
        },
        onPointerCancel: (_) {
          _pointerCount = 0;
          if (_isScaling) {
            setState(() {
              _isScaling = false;
            });
          }
        },
        child: GestureDetector(
          onScaleStart: (details) {
            _setScaleAlignment = false;
            _baseScale = _scale;
            if (_isScaling) {
              final box = _gridViewKey.currentContext?.findRenderObject();
              if (box is RenderBox) {
                final local = box.globalToLocal(details.focalPoint);
                setState(() {
                  // if(_scale==1){
                  //   _scaleAlignment = _alignmentForPoint(local, box.size);
                  // }
                  _updateScrollExtents();
                });
              }
            }
          },
          onScaleUpdate: (details) {
            setState(() {
              final nextScale =
                  (_baseScale * details.scale).clamp(0.9, 5.4).toDouble();
              if (_isScaling) {
                if (_scale < 5) {
                  _isScalingUp = nextScale > _scale;
                }
                if(_isScalingUp && _setScaleAlignment==false){
                  _setScaleAlignment = true;
                  final box = _gridBoxKey.currentContext?.findRenderObject();
                  if (box is RenderBox) {
                    final local = box.globalToLocal(details.focalPoint);
                    Alignment test = _alignmentForPoint(local, box.size);
                    Alignment newAlignment = test;
                    double x = test.x;
                    double y = test.y;
                    debugPrint('$test $x $y');
                    if(_scale == 1.6666){
                      if(_scaleAlignment == Alignment.centerRight){
                        if(test == Alignment.bottomCenter){
                          debugPrint('============');
                          // _scaleOrigin = Offset(-200, 0);
                          newAlignment = Alignment(0, 1);
                        }
                      }
                    }
                    // if(x>1) x = 1;
                    // if(y>1) y = 1;
                    // if(x<-1) x = -1;
                    // if(y<-1) y = -1;
                    _scaleAlignment = newAlignment;
                  }
                }
                _scale = nextScale;
                _updateScrollExtents();
              }
            });
          },
          onScaleEnd: (_) {
            // debugPrint('_isScalingUp $_isScalingUp');
            double? targetScale;
            if (_isScalingUp) { // scale up
              if (_scale < 2.5) {
                targetScale = _scale3Item;
              }else{
                targetScale = 5.0;
              }
            } else { // scale down
              if (_scale > _scale3Item) {
                targetScale = _scale3Item;
              } else {
                targetScale = 1.0;
              }
            }
            // if(_scale <= 1.25){ // 0 -> 1.25
            //   targetScale = 1;
            // }else if(1.25 < _scale && _scale <= 2.5){ // 1.25 -> 2.5
            //   targetScale = 1.6666;
            // }else if(2.5 < _scale){ // 2.5 -> ...
            //   targetScale = 5;
            // }
            // if(targetScale >= 5){
            //   // _gridTopPadding = 300;
            //   if(_scaleAlignment == Alignment.center){
            //     _gridTopPadding = 300;
            //   }else if(_scaleAlignment == Alignment.topCenter){
            //     _gridTopPadding = 0;
            //   }else if(_scaleAlignment == Alignment.bottomCenter){
            //     _gridTopPadding = 300;
            //   }
            // }else if(targetScale >= 1.6666){
            //   if(_scaleAlignment == Alignment.center){
            //     _gridTopPadding = 150;
            //   }else if(_scaleAlignment == Alignment.topCenter){
            //     _gridTopPadding = 0;
            //   }else if(_scaleAlignment == Alignment.bottomCenter){
            //     _gridTopPadding = 300;
            //   }
            // }else{
            //   _gridTopPadding = 0;
            // }
            // debugPrint(_scaleAlignment.);
            _scaleController.stop();
            _scaleAnimation = Tween<double>(
              begin: _scale,
              end: targetScale,
            ).animate(
              CurvedAnimation(
                parent: _scaleController,
                curve: Curves.easeOut,
              ),
            );
            _scaleController
              ..reset()
              ..forward();
          },
          child: Transform.scale(
            origin: _scaleOrigin,
            alignment: _scaleAlignment,
            scale: _scale,
            child: GridView.builder(
              key: _gridViewKey,
              controller: _controller,
              // physics: const NeverScrollableScrollPhysics(),
              physics: _isScaling
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _cols,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: _itemCount,
              itemBuilder: (context, index) {
                return Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor),
                  ),
                  child: Text('${index + 1}'),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PizGalleryScrollController extends ScrollController {
  double extraLeadingExtent = 0;
  double extraTrailingExtent = 0;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _PizGalleryScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      controller: this,
    );
  }
}

class _PizGalleryScrollPosition extends ScrollPositionWithSingleContext {
  _PizGalleryScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.controller,
  });

  final _PizGalleryScrollController controller;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final extraLeading =
        controller.extraLeadingExtent.clamp(0.0, double.infinity).toDouble();
    final extraTrailing =
        controller.extraTrailingExtent.clamp(0.0, double.infinity).toDouble();
    return super.applyContentDimensions(
      minScrollExtent - extraLeading,
      maxScrollExtent + extraTrailing,
    );
  }
}
