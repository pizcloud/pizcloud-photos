import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PizGallery2 extends StatefulWidget {
  const PizGallery2({super.key});

  @override
  State<PizGallery2> createState() => _PizGallery2State();
}

class _PizGallery2State extends State<PizGallery2>
    with SingleTickerProviderStateMixin {
  static const bool _showDebugBorders = true;
  static const Color _viewerBorderColor = Color(0xFFE53935);
  static const Color _scrollViewBorderColor = Color(0xFF1E88E5);
  static const Color _gridItemBorderColor = Color(0xFF43A047);
  static const int _pageSize = 60;
  static const double _gridPadding = 0;
  static const int _crossAxisCount = 5;
  static const double _crossAxisSpacing = 0;
  static const double _mainAxisSpacing = 0;
  static const int _imageCount = 100000;
  final _PizGallery2ScrollController _controller =
      _PizGallery2ScrollController();
  final TransformationController _transformController =
      TransformationController();
  final GlobalKey _scrollViewKey = GlobalKey();
  List<String> _imageUrls5 = [];
  List<String> _imageUrls = [];
  int _itemCount = _pageSize;
  int _activePointers = 0;
  bool _isScaling = false;
  bool _isScalingUp = false;
  double _lastGestureScale = 1.0;
  Offset? _lastFocalPoint;
  late final AnimationController _snapController;
  Animation<Matrix4>? _snapAnimation;
  int _viewCols = 5;

  @override
  void initState() {
    super.initState();
    _imageUrls5 = List.generate(
      _imageCount,
      (index) => "https://picsum.photos/id/${index}/1000",
      // (index) => 'https://dummyimage.com/600x300/fff/000&text=${index}'
    );
    _imageUrls = List.from(_imageUrls5);
    // _imageUrls = [
    //     ...List.filled(100, ''),
    //     ...List.from(_imageUrls5),
    // ];

    // scrollToFirstRealItem();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // _controller.jumpTo(20000);
      // scrollToFirstRealItem();
    });

    _controller.addListener(_onScroll);
    _transformController.addListener(_handleTransformChanged);
    _snapController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addListener(() {
          final nextValue = _snapAnimation?.value;
          if (nextValue != null) {
            _transformController.value = nextValue;
          }
        });
  }

  void scrollToFirstRealItem() {
    int firstRealIndex = 10;
        // _imageUrls.indexWhere((e) => e != '');

    if (firstRealIndex == -1) return;
    int crossAxisCount = 5;
    final RenderBox? box =
        _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final double viewportWidth = box.size.width;
    double rowHeight = viewportWidth / 5;
    int rowIndex = firstRealIndex ~/ crossAxisCount;
    // offset scroll
    double offset = rowIndex * rowHeight;
    _controller.jumpTo(offset);
    debugPrint("firstRealIndex = $firstRealIndex, rowIndex = $rowIndex");
    debugPrint("offset = $offset, rowHeight = $rowHeight");
  }

  @override
  void dispose() {
    _snapController.dispose();
    _transformController.removeListener(_handleTransformChanged);
    _transformController.dispose();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final double maxExtent =
        (position.maxScrollExtent - _controller.extraTrailingExtent).clamp(
          0.0,
          double.infinity,
        );
    if (position.pixels >= maxExtent - 200) {
      setState(() {
        if (_itemCount < _imageUrls.length) {
          _itemCount = (_itemCount + _pageSize).clamp(0, _imageUrls.length);
        }
        debugPrint('_itemCount $_itemCount');
      });
    }
  }

  void _setScaling(bool value) {
    if (_isScaling == value) return;
    setState(() {
      _isScaling = value;
    });
  }

  void _handleTransformChanged() {
    _updateScrollExtents();
  }

  void _updateScrollExtents() {
    if (!_controller.hasClients) return;
    final renderBox =
        _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final Size size = renderBox.size;
    final Matrix4 matrix = _transformController.value;
    final double scale = matrix.getMaxScaleOnAxis();

    double nextLeading = 0;
    double nextTrailing = 0;
    if (scale > 1.0) {
      final storage = matrix.storage;
      final double ty = storage[13];
      final double leading = (-ty / scale).clamp(0.0, double.infinity);
      final double trailing = (size.height * (1 - 1 / scale) + ty / scale)
          .clamp(0.0, double.infinity);
      nextLeading = leading;
      nextTrailing = trailing;
    }

    if ((_controller.extraLeadingExtent - nextLeading).abs() < 0.5 &&
        (_controller.extraTrailingExtent - nextTrailing).abs() < 0.5) {
      return;
    }

    setState(() {
      _controller.extraLeadingExtent = nextLeading;
      _controller.extraTrailingExtent = nextTrailing;
    });
  }

  void _updateScalingFromPointers() {
    _setScaling(_activePointers > 1);
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers += 1;
    _updateScalingFromPointers();
  }

  void to3Cols(int focusedIndex) {
    int realColIndex = focusedIndex - 1;
    // int j = realColIndex;
    for (int i = realColIndex; i >= 0; i--) {
      if (i % 5 == 0 || (i + 1) % 5 == 0) {
      } else {
        if (realColIndex >= 0) {
          _imageUrls[i] = _imageUrls5[realColIndex];
          realColIndex--;
        }
        debugPrint('realColIndex $realColIndex');
      }
    }

    int realColIndex2 = focusedIndex + 1;
    for (int i = realColIndex2; i < _imageUrls5.length; i++) {
      if (i % 5 == 0 || (i + 1) % 5 == 0) {
      } else {
        if (realColIndex2 < _imageUrls5.length) {
          _imageUrls[i] = _imageUrls5[realColIndex2];
          realColIndex2++;
        }
      }
    }

    List<String> images = [];
    for (int i = realColIndex; i >= 0; i -= 3) {
      images.insertAll(0, [
        _imageUrls5[0],
        i - 2 >= 0 ? _imageUrls5[i - 2] : _imageUrls5[0],
        i - 1 >= 0 ? _imageUrls5[i - 1] : _imageUrls5[0],
        _imageUrls5[i],
        _imageUrls5[0],
      ]);
      // realColIndex--;
      debugPrint('realColIndex22 $i');
    }
    debugPrint('images ${images.length}, $images');
    // insertRowAtTop(images);
    setState(() {});
  }

  void insertRowAtTop(List<String> newItems) {
    if (!_controller.hasClients) return;
    if (newItems.isEmpty) return;

    // 1. Lưu offset hiện tại trước khi insert
    final double oldOffset = _controller.offset;

    // 2. Tính scale hiện tại của InteractiveViewer
    // final double scale =  _transformController.value.getMaxScaleOnAxis();

    // 3. Lấy kích thước viewport để tính itemHeight
    final RenderBox? box =
        _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;

    if (box == null || !box.hasSize) return;

    final double viewportWidth = box.size.width;

    // 4. Grid item height (vì item vuông)
    final double itemHeight = viewportWidth / 5;

    // 5. Số row mới insert vào đầu
    final int insertedRows = (newItems.length / 5).ceil();

    // 6. Tổng chiều cao content mới thêm (phải nhân scale)
    final double deltaOffset = insertedRows * itemHeight;

    // 7. Insert dữ liệu vào đầu list
    setState(() {
      _imageUrls.insertAll(0, newItems);

      // Nếu bạn muốn itemCount tăng luôn
      _itemCount = (_itemCount + newItems.length).clamp(0, _imageUrls.length);
    });

    // 8. Sau khi frame render xong mới jump offset
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;

      _controller.jumpTo(oldOffset + deltaOffset);
    });
  }

  void _handlePointerUp(PointerUpEvent event) async {
    final bool wasScaling = _activePointers > 1;
    _activePointers = (_activePointers - 1).clamp(0, 10);
    _updateScalingFromPointers();
    if (wasScaling && _activePointers < 2) {
      final focusedIndex = _getFocusedCellIndex();
      await _maybeSnapScale();
      if (focusedIndex != null) {
        debugPrint('focused cell index $focusedIndex view cols $_viewCols');
        if (_viewCols == 3) {
          to3Cols(focusedIndex);
        } else {
          _imageUrls = List.from(_imageUrls5);
          setState(() {});
        }
      }
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    final bool wasScaling = _activePointers > 1;
    _activePointers = (_activePointers - 1).clamp(0, 10);
    _updateScalingFromPointers();
    if (wasScaling && _activePointers < 2) {
      _maybeSnapScale();
    }
  }

  void _handleInteractionStart(ScaleStartDetails details) {
    _lastFocalPoint = details.localFocalPoint;
    // _isScalingUp = false;
    _lastGestureScale = 1.0;
  }

  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    _lastFocalPoint = details.localFocalPoint;
    if (_isScaling) {
      _isScalingUp = details.scale > _lastGestureScale;
    }
    debugPrint('_isScalingUp $_isScalingUp');

    _lastGestureScale = details.scale;
    // _clampToMinScale();
  }

  Future<void> _maybeSnapScale() async {
    final double currentScale = _transformController.value.getMaxScaleOnAxis();
    double? targetScale;
    if (_isScalingUp) {
      if (currentScale < 1.6666) {
        targetScale = 1.6666;
        _viewCols = 3;
      } else if (currentScale < 2.5) {
        targetScale = 1.6666;
        _viewCols = 3;
      } else {
        targetScale = 5;
        _viewCols = 1;
      }
    } else {
      if (currentScale > 1.6666) {
        targetScale = 1.6666;
        _viewCols = 3;
      } else {
        targetScale = 1;
        _viewCols = 5;
      }
    }

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final Size size = renderBox.size;
    Matrix4 target;
    // target = Matrix4.identity();
    // if (targetScale <= minScale) {
    //   target = Matrix4.identity();
    // } else {
    final Offset focal =
        _lastFocalPoint ?? Offset(size.width / 2, size.height / 2);
    final Offset scenePoint = _transformController.toScene(focal);
    target = Matrix4.identity()
      ..translate(focal.dx, focal.dy)
      ..scale(targetScale)
      ..translate(-scenePoint.dx, -scenePoint.dy);
    debugPrint('size.width ${size.width} ');
    debugPrint('scenePoint.dx $scenePoint ');
    target = _snapToNearestColumnBorder(Matrix4.copy(target), size);
    target = _clampGridToViewportEdges(target, size);
    // }

    final box = _scrollViewKey.currentContext!.findRenderObject() as RenderBox;
    final size2 = box.size;
    debugPrint("CustomScrollView size: $size2");
    final position = box.localToGlobal(Offset.zero);
    debugPrint("CustomScrollView position: $position");

    _snapController.stop();
    _snapAnimation = Matrix4Tween(
      begin: _transformController.value,
      end: target,
    ).animate(CurvedAnimation(parent: _snapController, curve: Curves.easeOut));
    await _snapController.forward(from: 0);
  }

  Matrix4 _clampGridToViewportEdges(Matrix4 matrix, Size size) {
    final double scale = matrix.getMaxScaleOnAxis();
    // if (scale <= 1) return matrix;

    final double contentWidth = size.width - (_gridPadding * 2);
    if (contentWidth <= 0) return matrix;
    final double contentHeight = size.height - (_gridPadding * 2);
    if (contentHeight <= 0) return matrix;

    final storage = matrix.storage;
    final double tx = storage[12];
    final double ty = storage[13];
    final double leftEdge = tx + scale * _gridPadding;
    final double rightEdge = tx + scale * (_gridPadding + contentWidth);
    final double topEdge = ty + scale * _gridPadding;
    final double bottomEdge = ty + scale * (_gridPadding + contentHeight);
    double shiftX = 0;
    double shiftY = 0;
    if (leftEdge > 0) {
      shiftX = -leftEdge;
    } else if (rightEdge < size.width) {
      shiftX = size.width - rightEdge;
    }
    if (topEdge > 0) {
      shiftY = -topEdge;
    } else if (bottomEdge < size.height) {
      shiftY = size.height - bottomEdge;
    }
    if (shiftX.abs() < 0.5 && shiftY.abs() < 0.5) return matrix;

    matrix.setTranslationRaw(tx + shiftX, ty + shiftY, storage[14]);
    return matrix;
  }

  Matrix4 _snapToNearestColumnBorder(Matrix4 matrix, Size size) {
    final double scale = matrix.getMaxScaleOnAxis();
    if (scale <= 1) return matrix;

    final double contentWidth = size.width - (_gridPadding * 2);
    if (contentWidth <= 0) return matrix;

    final double itemWidth =
        (contentWidth - (_crossAxisCount - 1) * _crossAxisSpacing) /
        _crossAxisCount;
    if (itemWidth <= 0) return matrix;

    final double stride = itemWidth + _crossAxisSpacing;
    final storage = matrix.storage;
    final double tx = storage[12];
    final double ty = storage[13];

    double dxForEdge(double edgeX) {
      final double xScene = (edgeX - tx) / scale;
      double nearestBorder(double offset) {
        final double k = ((xScene - offset) / stride).roundToDouble();
        return offset + k * stride;
      }

      final double borderA = nearestBorder(_gridPadding);
      final double borderB = nearestBorder(_gridPadding + itemWidth);
      final double nearest =
          (xScene - borderA).abs() <= (xScene - borderB).abs()
          ? borderA
          : borderB;
      return (xScene - nearest) * scale;
    }

    final double dxLeft = dxForEdge(0);
    final double dxRight = dxForEdge(size.width);
    final double dx = dxLeft.abs() <= dxRight.abs() ? dxLeft : dxRight;
    if (dx.abs() < 0.5) return matrix;

    matrix.setTranslationRaw(tx + dx, ty, storage[14]);
    return matrix;
  }

  int? _getFocusedCellIndex() {
    if (!_controller.hasClients) return null;
    final RenderBox? renderBox =
        _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;

    final Size size = renderBox.size;
    final Offset fallbackFocal = Offset(size.width / 2, size.height / 2);
    final Offset focal = _lastFocalPoint ?? fallbackFocal;
    final Offset scenePoint = _transformController.toScene(focal);

    final double contentWidth = size.width - (_gridPadding * 2);
    if (contentWidth <= 0) return null;
    final double itemWidth =
        (contentWidth - (_crossAxisCount - 1) * _crossAxisSpacing) /
        _crossAxisCount;
    if (itemWidth <= 0) return null;

    final double strideX = itemWidth + _crossAxisSpacing;
    final double strideY = itemWidth + _mainAxisSpacing;
    final double scrollOffset = _controller.position.pixels;

    final double x = scenePoint.dx - _gridPadding;
    final double y = scenePoint.dy - _gridPadding + scrollOffset;
    if (x < 0 || y < 0) return null;

    final int col = (x / strideX).floor();
    final int row = (y / strideY).floor();
    if (col < 0 || col >= _crossAxisCount || row < 0) return null;

    final double xInCell = x - col * strideX;
    final double yInCell = y - row * strideY;
    if (xInCell > itemWidth || yInCell > itemWidth) return null;

    final int index = row * _crossAxisCount + col;
    if (index < 0 || index >= _itemCount) return null;
    return index;
  }

  Widget _buildGridSliver(Color borderColor) {
    return SliverPadding(
      padding: const EdgeInsets.all(_gridPadding),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((context, index) {
          final imageUrl = _imageUrls[index];
          return Container(
            key: ValueKey('c $imageUrl'),
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border.all(color: Colors.black)),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 1350),

              // ✅ Hiệu ứng fade-out ảnh cũ + fade-in ảnh mới
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },

              // ⚠️ Key bắt buộc để Flutter biết ảnh đã đổi
              child: CachedNetworkImage(
                key: ValueKey(imageUrl),
                imageUrl: _imageUrls[index],
                fit: BoxFit.cover,
                // fadeInDuration: const Duration(milliseconds: 200),
                // fadeOutDuration: const Duration(milliseconds: 200),

                // Placeholder khi loading
                placeholder: (context, url) => Container(
                  color: Colors.grey.shade300,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),

                // Error
                errorWidget: (context, url, error) =>
                    const Icon(Icons.broken_image),
                // errorBuilder: (context, error, stackTrace) {
                //   return const Icon(Icons.broken_image);
                // },
              ),
            ),
          );
        }, childCount: _itemCount),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _crossAxisCount,
          mainAxisSpacing: _mainAxisSpacing,
          crossAxisSpacing: _crossAxisSpacing,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _showDebugBorders
        ? _gridItemBorderColor
        : Theme.of(context).dividerColor;
    final scrollView = CustomScrollView(
      // reverse: true,
      key: _scrollViewKey,
      controller: _controller,
      physics: _isScaling ? const NeverScrollableScrollPhysics() : null,
      slivers:
      [
        // SliverToBoxAdapter(child: SizedBox(height: 20000)),
        _buildGridSliver(borderColor)
      ],
    );
    final scrollViewWithBorder = _showDebugBorders
        ? DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: _scrollViewBorderColor, width: 2),
            ),
            child: scrollView,
          )
        : scrollView;
    final viewer = InteractiveViewer(
      transformationController: _transformController,
      minScale: 1.0,
      maxScale: 5.0,
      panEnabled: false,
      scaleEnabled: true,
      onInteractionStart: _handleInteractionStart,
      onInteractionUpdate: _handleInteractionUpdate,
      child: Listener(
        onPointerDown: _handlePointerDown,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: scrollViewWithBorder,
      ),
    );
    if (!_showDebugBorders) return viewer;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: _viewerBorderColor, width: 2),
      ),
      child: viewer,
    );
  }
}

class _PizGallery2ScrollController extends ScrollController {
  double extraLeadingExtent = 0;
  double extraTrailingExtent = 0;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _PizGallery2ScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      controller: this,
    );
  }
}

class _PizGallery2ScrollPosition extends ScrollPositionWithSingleContext {
  _PizGallery2ScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.controller,
  });

  final _PizGallery2ScrollController controller;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final extraLeading = controller.extraLeadingExtent
        .clamp(0.0, double.infinity)
        .toDouble();
    final extraTrailing = controller.extraTrailingExtent
        .clamp(0.0, double.infinity)
        .toDouble();
    return super.applyContentDimensions(
      minScrollExtent - extraLeading,
      maxScrollExtent + extraTrailing,
    );
  }
}
