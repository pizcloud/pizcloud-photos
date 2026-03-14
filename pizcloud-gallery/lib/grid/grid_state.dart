import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'grid_state_helper.dart';
import 'grid_window.dart';

class FocusCell {
  final int row;
  final int col;
  final int colCount;
  final int index;

  FocusCell({
    required this.row,
    required this.col,
    required this.colCount,
    required this.index,
  });

  @override
  String toString() =>
      "FocusCell(row: $row, col: $col, colCount: $colCount, index: $index)";
}

class GridState {
  // Controllers
  final ScrollController verticalController = ScrollController();
  final ScrollController horizontalController = ScrollController();

  final TransformationController transformController =
      TransformationController();
  final AnimationController animController;
  Animation<double>? _scaleAnim;
  Animation<Offset>? _translateAnim;
  VoidCallback? _animListener;
  final gridKey = GlobalKey();
  final containerKey = GlobalKey();

  // Grid config
  final int defaultColCount;
  // int currentColCount;
  double cellSize = 80;
  int currentColCount;
  int targetColCount = 5;
  final VoidCallback? onSizeChanged;

  // Virtual rows (infinite)
  // int rowCount;
  int baseRow = 0;
  List<int> baseCells = [0, 0, 0, 0, 0, 0];
  int totalCells;
  int totalDataCells;
  int get rowCount => getRowCount();
  int viewportFirstCol = 0;
  int firstCellCol = 0;
  Size _cachedViewportSize = Size.zero;

  // Scroll notifier
  final ValueNotifier<Offset> scrollOffset = ValueNotifier(const Offset(0, 0));
  final ValueNotifier<bool> isScalingNotifier = ValueNotifier(false);
  final ValueNotifier<int> scaleDirectionNotifier = ValueNotifier(0);
  double _lastObservedScale = 1.0;

  // Focal tracking (in scene space) for snap animation
  Offset? _lastFocal;

  // Pointer scaling lock
  int pointerCount = 0;

  // Prepend lock
  bool loadingTop = false;
  bool _isFastScrollActive = false;
  VoidCallback? _scrollActivityListener;
  ScrollPosition? _scrollActivityPosition;
  double lockTopOffset = 0.0;
  double lockBottomOffset = 0.0;

  FocusCell? focusCell;
  bool _isClampingScroll = false;
  AnimationStatusListener? _animStatusListener;

  GridState({
    required this.defaultColCount,
    required this.totalDataCells,
    required TickerProvider vsync,
    this.onSizeChanged,
  }) : totalCells = totalDataCells,
       currentColCount = defaultColCount,
       animController = AnimationController(
         vsync: vsync,
         duration: const Duration(milliseconds: 500),
       );

  // =======================================================
  // Init listeners
  // =======================================================
  void init() {
    verticalController.addListener(_updateOffset);
    horizontalController.addListener(_updateOffset);
    verticalController.addListener(_onVerticalScroll);
    transformController.addListener(_handleTransform);
    _lastObservedScale = getCurrentScale();
    // transformController.addListener(_clampTransformToContent);
  }

  void updateViewportSize(Size viewport) {
    if (!viewport.width.isFinite || !viewport.height.isFinite) return;
    if (viewport.width <= 0 || viewport.height <= 0) return;
    _cachedViewportSize = viewport;
  }

  void updateTargetColCount() {
    final double scale = transformController.value.getMaxScaleOnAxis();
    updateScaleDirectionFromScale(scale: scale);
    final decision = GridStateHelper.resolveScaleDecision(
      scale: scale,
      currentColCount: currentColCount,
      scaleDirection: scaleDirection,
    );
    targetColCount = decision.colCount;

    // debugPrint('targetColCount $targetColCount, currentColCount $currentColCount');
    if (targetColCount != currentColCount) {
      // debugPrint('targetColCount $targetColCount, currentColCount $currentColCount');
      // debugPrint('targetColCount $targetColCount, scale: $scale');
      // updateBaseCell(targetColCount);
      // currentColCount = targetColCount;
      // updateFirstCellCol();
      // onSizeChanged?.call();
    }
  }

  int get scaleDirection => scaleDirectionNotifier.value;

  void beginScaleDirectionTracking() {
    _lastObservedScale = getCurrentScale();
    scaleDirectionNotifier.value = 0;
  }

  void updateScaleDirectionFromScale({double? scale, double epsilon = 0.01}) {
    final double currentScale = scale ?? getCurrentScale();
    final double delta = currentScale - _lastObservedScale;
    if (delta > epsilon) {
      scaleDirectionNotifier.value = 1;
    } else if (delta < -epsilon) {
      scaleDirectionNotifier.value = -1;
    }
    // _lastObservedScale = currentScale;
  }

  void endScaleDirectionTracking({double epsilon = 0.01}) {
    updateScaleDirectionFromScale(epsilon: epsilon);
  }

  void resetScaleDirection() {
    scaleDirectionNotifier.value = 0;
    _lastObservedScale = getCurrentScale();
  }

  void _handleTransform() {
    if (_isClampingScroll) return;
    if (!verticalController.hasClients) return;
    if (!GridStateHelper.isValidCellSize(cellSize)) return;

    updateTargetColCount();

    final position = verticalController.position;
    final double scrollY = position.pixels;
    final Matrix4 m = transformController.value;
    final double scale = GridStateHelper.safeScale(m);
    // final double tx = GridStateHelper.translateX(m);
    final double ty = GridStateHelper.translateY(m);
    updateViewportFirstCol();
    final double baseTopY = _baseTopYForIndex0(colCount: targetColCount);
    // debugPrint('baseTopY $baseTopY');

    final Size viewport = _viewportSize();
    if (!viewport.isEmpty && viewport.height.isFinite) {
      final double dataHeight = targetDataSize().height;
      if (dataHeight.isFinite && dataHeight > 0) {
        // final double scaledDataHeight = dataHeight * scale;
        final double extraSpace = viewport.height - dataHeight;
        if (extraSpace > 0.5) {
          // final double baseTopScreen = (baseTopY - scrollY) * scale;
          // final double targetTy = -baseTopScreen;
          // if ((targetTy - ty).abs() > 0.5) {
          _isClampingScroll = true;
          jumpToFirstDataRow();
          updateBaseCell(targetColCount);
          clampToTopWhenContentShort();
          clampScrollToFirstCell();
          transformController.value = Matrix4.identity()
            ..translateByDouble(0.0, 0.0, 0.0, 1.0)
            ..scaleByDouble(scale, scale, 1.0, 1.0);
          _isClampingScroll = false;
          // }
          return;
        }
      }
    }
    clampToTopWhenContentShort();
    updateBaseCell(targetColCount);
    _clampScrollToDataEnd();
    // clampScrollToFirstCell();
    // _clampScrollToDataEnd();

    // isContentTopInsideViewportFast();

    // Prefer correcting via scroll offset so the scrollbar represents
    // the full viewport. Only clamp translate when scroll hits an extent.
    final double topContentY = GridStateHelper.topContentY(
      scrollY: scrollY,
      translateY: ty,
      scale: scale,
    );
    if (topContentY >= baseTopY - 0.5) return;

    final double desiredScrollY = GridStateHelper.targetScrollYForBaseTop(
      baseTopY: baseTopY,
      translateY: ty,
      scale: scale,
    );
    final double clampedScrollY = GridStateHelper.clampToScrollExtents(
      value: desiredScrollY,
      position: position,
    );

    final bool shouldScroll = (clampedScrollY - scrollY).abs() > 0.5;
    final double maxTy = (clampedScrollY - baseTopY) * scale;
    final bool shouldClampTranslate = ty > maxTy + 0.5;

    if (!shouldScroll && !shouldClampTranslate) return;

    _isClampingScroll = true;
    if (shouldScroll) {
      // debugPrint('jumpTo(clampedScrollY)');
      verticalController.jumpTo(clampedScrollY);
    }
    // if (shouldClampTranslate) {
    //   transformController.value = Matrix4.identity()
    //     ..translate(tx, 0)
    //     ..scale(scale);
    // }
    _isClampingScroll = false;
  }

  Size dataSize() {
    final double scale = GridStateHelper.safeScale(transformController.value);
    double width = currentColCount * cellSize;
    double height = getDataRowCount(currentColCount) * cellSize * scale;
    return Size(width, height);
  }

  Size targetDataSize() {
    final double scale = GridStateHelper.safeScale(transformController.value);
    double width = targetColCount * cellSize;
    double height = getDataRowCount(targetColCount) * cellSize * scale;
    return Size(width, height);
  }

  bool isContentTopInsideViewportFast() {
    final Matrix4 m = transformController.value;
    final double scale = m.getMaxScaleOnAxis().clamp(0.0001, 1000.0);
    final double translateY = m.storage[13];

    final double topYForIndex0 = _baseTopYForIndex0();
    final double scrollOffset = verticalController.offset;

    // Screen-space top of the row that contains index 0.
    final double top = (topYForIndex0 - scrollOffset) * scale + translateY;
    debugPrint(
      'scale $scale '
      'translateY $translateY '
      'topYForIndex0 $topYForIndex0 '
      'scrollOffset $scrollOffset '
      'top $top',
    );

    return top >= 0;
  }

  void _onVerticalScroll() {
    if (_isClampingScroll) {
      return;
    }
    _attachScrollActivityListenerIfNeeded();
    if (_isFastScrollActive) {
      return;
    }
    _runVerticalScrollMaintenance();
  }

  void _runVerticalScrollMaintenance({bool forceClamp = false}) {
    _refreshScrollLockOffsets();
    if (!forceClamp) {
      handleInfinitePrepend();
      handleInfiniteAppend();
    }
    if (!forceClamp && _shouldDeferClampDuringActiveScroll()) {
      return;
    }
    // if (jumpToFirstDataRowIfContentShort()) return;
    // if(firstCellCol > viewportFirstCol){
    //   baseCells[currentColCount] =  baseCells[currentColCount] -  (firstCellCol - viewportFirstCol);
    //   firstCellCol = viewportFirstCol;
    // }
    if (_isContentShortForViewport()) {
      clampScrollToFirstCellWhenContentShort();
      clampToTopWhenContentShort();
    } else {
      clampScrollToFirstCell();
      _clampScrollToDataEnd();
    }
    /*clampToTopWhenContentShort();
    if (!clampScrollToFirstCellWhenContentShort()) {
      clampScrollToFirstCell();
    }
    // clampScrollToFirstCellWhenContentShort();
    _clampScrollToDataEnd();*/
  }

  void _attachScrollActivityListenerIfNeeded() {
    if (!verticalController.hasClients) {
      return;
    }
    final ScrollPosition position = verticalController.position;
    if (_scrollActivityPosition == position &&
        _scrollActivityListener != null) {
      return;
    }
    if (_scrollActivityPosition != null && _scrollActivityListener != null) {
      _scrollActivityPosition!.isScrollingNotifier.removeListener(
        _scrollActivityListener!,
      );
    }
    _scrollActivityListener = () {
      if (!verticalController.hasClients) {
        return;
      }
      if (_scrollActivityPosition != verticalController.position) {
        _attachScrollActivityListenerIfNeeded();
        return;
      }
      if (pointerCount > 0) {
        return;
      }
      if (position.isScrollingNotifier.value) {
        return;
      }
      if (_isFastScrollActive) {
        return;
      }
      _runVerticalScrollMaintenance(forceClamp: true);
    };
    _scrollActivityPosition = position;
    position.isScrollingNotifier.addListener(_scrollActivityListener!);
  }

  bool _shouldDeferClampDuringActiveScroll() {
    if (!verticalController.hasClients) {
      return false;
    }
    if (pointerCount > 0) {
      return true;
    }
    final ScrollPosition position = verticalController.position;
    return position.isScrollingNotifier.value ||
        position.userScrollDirection != ScrollDirection.idle;
  }

  ({double minScrollY, double maxScrollY})? _resolveDataScrollBounds() {
    if (!verticalController.hasClients) return null;
    if (!GridStateHelper.isValidCellSize(cellSize)) return null;
    if (totalDataCells <= 0) return null;
    final Size viewport = _viewportSize();
    if (!GridStateHelper.isValidViewport(viewport)) return null;

    updateViewportFirstCol();
    final ScrollPosition position = verticalController.position;
    final Matrix4 matrix = transformController.value;
    final double scale = GridStateHelper.safeScale(matrix);
    final double ty = GridStateHelper.translateY(matrix);
    final double baseTopY = _baseTopYForIndex0();

    final double minScrollY = GridStateHelper.clampToScrollExtents(
      value: GridStateHelper.targetScrollYForBaseTop(
        baseTopY: baseTopY,
        translateY: ty,
        scale: scale,
      ),
      position: position,
    );

    final int dataRows = getDataRowCount();
    final double dataBottomY = baseTopY + dataRows * cellSize;
    final double rawMaxScrollY =
        dataBottomY - (viewport.height / scale) + (ty / scale);
    final double maxScrollY = GridStateHelper.clampToScrollExtents(
      value: rawMaxScrollY,
      position: position,
    );

    if (maxScrollY < minScrollY) {
      return (minScrollY: minScrollY, maxScrollY: minScrollY);
    }
    return (minScrollY: minScrollY, maxScrollY: maxScrollY);
  }

  void _refreshScrollLockOffsets() {
    final ({double minScrollY, double maxScrollY})? bounds =
        _resolveDataScrollBounds();
    if (bounds == null) {
      if (verticalController.hasClients) {
        final double current = verticalController.position.pixels;
        lockTopOffset = current;
        lockBottomOffset = current;
      } else {
        lockTopOffset = 0.0;
        lockBottomOffset = 0.0;
      }
      return;
    }
    lockTopOffset = bounds.minScrollY;
    lockBottomOffset = bounds.maxScrollY < bounds.minScrollY
        ? bounds.minScrollY
        : bounds.maxScrollY;
  }

  ({double lockTopOffset, double lockBottomOffset}) getScrollLockOffsets() {
    _refreshScrollLockOffsets();
    return (lockTopOffset: lockTopOffset, lockBottomOffset: lockBottomOffset);
  }

  void setFastScrollActive(bool active) {
    if (_isFastScrollActive == active) return;
    _isFastScrollActive = active;
    if (!active) {
      _runVerticalScrollMaintenance(forceClamp: true);
    }
  }

  bool clampScrollToFirstCellWhenContentShort() {
    if (_isClampingScroll) return false;
    if (!verticalController.hasClients) return false;
    if (!GridStateHelper.isValidCellSize(cellSize)) return false;

    final Size viewport = _viewportSize();
    if (!GridStateHelper.isValidViewport(viewport)) return false;
    if (dataSize().height > viewport.height + 0.5) return false;

    clampScrollToFirstCell();
    return true;
  }

  bool jumpToFirstDataRowIfContentShort() {
    if (_isClampingScroll) return false;
    if (!verticalController.hasClients) return false;
    if (!GridStateHelper.isValidCellSize(cellSize)) return false;

    final Size viewport = _viewportSize();
    if (!GridStateHelper.isValidViewport(viewport)) return false;

    final double dataHeight = dataSize().height;
    if (!dataHeight.isFinite || dataHeight >= viewport.height - 0.5) {
      return false;
    }

    final Matrix4 m = transformController.value;
    final double scale = GridStateHelper.safeScale(m);
    final double ty = GridStateHelper.translateY(m);
    final double scrollY = verticalController.position.pixels;
    final double targetScrollY = GridStateHelper.targetScrollYForBaseTop(
      baseTopY: getFirstDataRow() * cellSize,
      translateY: ty,
      scale: scale,
    );
    final double clampedTarget = GridStateHelper.clampToScrollExtents(
      value: targetScrollY,
      position: verticalController.position,
    );

    if ((clampedTarget - scrollY).abs() <= 0.5) return false;
    _isClampingScroll = true;
    verticalController.jumpTo(clampedTarget);
    _isClampingScroll = false;
    return true;
  }

  void clampToTopWhenContentShort() {
    if (_isClampingScroll) return;
    if (!verticalController.hasClients) return;
    if (!GridStateHelper.isValidCellSize(cellSize)) return;

    final Size viewport = _viewportSize();
    if (!GridStateHelper.isValidViewport(viewport)) return;
    if (dataSize().height >= viewport.height) return;
    // debugPrint('(dataSize().height: ${dataSize().height}, viewport: ${viewport.height*2/3} ');

    final position = verticalController.position;
    final double scrollY = position.pixels;
    updateViewportFirstCol();
    final double baseTopY = _baseTopYForIndex0();

    final Matrix4 m = transformController.value;
    final double scale = GridStateHelper.safeScale(m);
    final double ty = GridStateHelper.translateY(m);

    // Opposite of _clampScrollToFirstCell:
    // do not allow first cell to move above the viewport top.
    final double topContentY = GridStateHelper.topContentY(
      scrollY: scrollY,
      translateY: ty,
      scale: scale,
    );
    if (topContentY <= baseTopY + 0.5) return;

    final double targetScrollY = GridStateHelper.clampToScrollExtents(
      value: GridStateHelper.targetScrollYForBaseTop(
        baseTopY: baseTopY,
        translateY: ty,
        scale: scale,
      ),
      position: position,
    );
    if ((targetScrollY - scrollY).abs() <= 0.5) return;

    _isClampingScroll = true;
    verticalController.jumpTo(targetScrollY);
    _isClampingScroll = false;
  }

  void clampScrollToFirstCell() {
    if (_isClampingScroll) return;
    if (!verticalController.hasClients) return;
    if (!GridStateHelper.isValidCellSize(cellSize)) return;

    final position = verticalController.position;
    final double scrollY = position.pixels;

    final double baseTopY = _baseTopYForIndex0();

    final Matrix4 m = transformController.value;
    final double scale = GridStateHelper.safeScale(m);
    final double ty = GridStateHelper.translateY(m);

    final double topContentY = GridStateHelper.topContentY(
      scrollY: scrollY,
      translateY: ty,
      scale: scale,
    );
    // debugPrint('topContentY $topContentY, baseTopY, $baseTopY');

    if (topContentY < baseTopY) {
      final double targetScrollY = GridStateHelper.clampToScrollExtents(
        value: GridStateHelper.targetScrollYForBaseTop(
          baseTopY: baseTopY,
          translateY: ty,
          scale: scale,
        ),
        position: position,
      );
      // debugPrint('targetScrollY $targetScrollY, scrollY $scrollY');
      if ((targetScrollY - scrollY).abs() > 0.5) {
        _isClampingScroll = true;
        verticalController.jumpTo(targetScrollY);
        _isClampingScroll = false;
      }
    }
  }

  void _clampScrollToDataEnd() {
    if (_isClampingScroll) return;
    if (!verticalController.hasClients) return;
    if (!GridStateHelper.isValidCellSize(cellSize)) return;
    if (totalDataCells <= 0) return;

    final Size viewport = _viewportSize();
    if (!GridStateHelper.isValidViewport(viewport)) return;

    updateViewportFirstCol();
    final Matrix4 m = transformController.value;
    final double scale = GridStateHelper.safeScale(m);
    final double ty = GridStateHelper.translateY(m);

    final int dataRows = getDataRowCount();
    final double scaledDataHeight = dataRows * cellSize * scale;
    if (scaledDataHeight <= viewport.height + 0.5) return;

    // Bottom Y of the last row that still contains data (scene space).
    final double baseTopY = _baseTopYForIndex0();
    final double dataBottomY = baseTopY + dataRows * cellSize;
    final double maxScrollY =
        dataBottomY - (viewport.height / scale) + (ty / scale);

    final position = verticalController.position;
    final double clampedMax = GridStateHelper.clampToScrollExtents(
      value: maxScrollY,
      position: position,
    );

    if (verticalController.offset > clampedMax + 0.5) {
      _isClampingScroll = true;
      verticalController.jumpTo(clampedMax);
      _isClampingScroll = false;
    }
  }

  int getFirstDataRow() {
    return _floorDivInt(baseCells[currentColCount], currentColCount) - baseRow;
  }

  int getEndDataRow() {
    return getFirstDataRow() + getDataRowCount(currentColCount);
  }

  void jumpToFirstDataRow() {
    if (!verticalController.hasClients) return;
    if (!GridStateHelper.isValidCellSize(cellSize)) return;

    // First data row includes baseCell offset.
    final int firstDataRow = getFirstDataRow();
    final Matrix4 m = transformController.value;
    final double scale = GridStateHelper.safeScale(m);
    final double ty = GridStateHelper.translateY(m);

    final position = verticalController.position;
    final double targetScrollY = GridStateHelper.targetScrollYForBaseTop(
      baseTopY: firstDataRow * cellSize,
      translateY: ty,
      scale: scale,
    );
    final double clampedTarget = GridStateHelper.clampToScrollExtents(
      value: targetScrollY,
      position: position,
    );

    if ((clampedTarget - position.pixels).abs() <= 2) return;
    _isClampingScroll = true;
    verticalController.jumpTo(clampedTarget);
    _isClampingScroll = false;
  }

  void updateViewportFirstCol() {
    if (!GridStateHelper.isValidCellSize(cellSize)) return;
    final Matrix4 m = transformController.value;
    final double scale = GridStateHelper.safeScale(m); // avoid /0
    final double tx = GridStateHelper.translateX(m);
    final double leftX = -tx / scale;
    final int maxFirstCol = max(0, defaultColCount - currentColCount);
    final int col = (leftX / cellSize).round().clamp(0, maxFirstCol);
    viewportFirstCol = col;
    updateFirstCellCol(colCount: currentColCount, viewportCol: col);
  }

  int getViewportFirstCol() {
    if (!GridStateHelper.isValidCellSize(cellSize)) return 0;
    final Matrix4 m = transformController.value;
    final double scale = GridStateHelper.safeScale(m); // avoid /0
    final double tx = GridStateHelper.translateX(m);
    final double leftX = -tx / scale;
    final int maxFirstCol = max(0, defaultColCount - currentColCount);
    final int col = (leftX / cellSize).round().clamp(0, maxFirstCol);
    return col;
  }

  int computeFirstCellCol({int? colCount, int? viewportCol}) {
    final int cols = colCount ?? currentColCount;
    if (cols <= 0) return 0;

    final int maxFirstCol = max(0, defaultColCount - cols);
    final int leftCol = (viewportCol ?? viewportFirstCol).clamp(0, maxFirstCol);
    final int baseCell = baseCells[cols];

    // index = logicalRow * cols + col - baseCell
    // => col ≡ baseCell (mod cols). Pick first col in current viewport window.
    final int residue = ((baseCell % cols) + cols) % cols;
    final int delta = leftCol - residue;
    final int step = delta <= 0 ? 0 : (delta + cols - 1) ~/ cols;
    final int col = residue + step * cols;
    final int maxVisibleCol = min(defaultColCount - 1, leftCol + cols - 1);
    return col.clamp(leftCol, maxVisibleCol);
  }

  void updateFirstCellCol({int? colCount, int? viewportCol}) {
    // debugPrintTable();

    // if(focusCell != null && focusCell!.index == -1){
    //   firstCellCol = viewportFirstCol;
    //   debugPrint('updateFirstCellCol: firstCellCol: $firstCellCol, viewportFirstCol $viewportFirstCol');
    // }else{
    firstCellCol = computeFirstCellCol(
      colCount: colCount,
      viewportCol: viewportCol,
    );
    // debugPrint('computeFirstCellCol: firstCellCol: $firstCellCol, viewportFirstCol $viewportFirstCol');
    // }
  }

  /// Floor division for int with negatives (Dart ~/ truncates).
  int _floorDivInt(int a, int b) {
    // b > 0
    if (a >= 0) return a ~/ b;
    return -(((-a) + b - 1) ~/ b);
  }

  int logicalRowOfDataStart({int? colCount, int? leftCol}) {
    final int cols = colCount ?? currentColCount;
    if (cols <= 0) return 0;
    final int resolvedLeftCol = leftCol ?? viewportFirstCol;
    final int baseCell = baseCells[cols] - resolvedLeftCol;
    return _floorDivInt(baseCell, cols);
  }

  double currentLogicalTopRow() {
    if (!verticalController.hasClients || cellSize <= 0) {
      return baseRow.toDouble();
    }
    final Matrix4 m = transformController.value;
    final double scale = GridStateHelper.safeScale(m);
    final double ty = GridStateHelper.translateY(m);
    final double logicalTop = verticalController.offset - (ty / scale);
    return baseRow + (logicalTop / cellSize);
  }

  double currentRealTopRow({int? colCount, int? leftCol}) {
    final double logicalTopRow = currentLogicalTopRow();
    final int logicalDataStart = logicalRowOfDataStart(
      colCount: colCount,
      leftCol: leftCol,
    );
    return logicalTopRow - logicalDataStart;
  }

  int realDataRowCount({int? colCount}) {
    return getDataRowCount(colCount ?? currentColCount);
  }

  double visibleDataRowsInViewport(double viewportHeight) {
    if (cellSize <= 0) return 0;
    if (!viewportHeight.isFinite || viewportHeight <= 0) return 0;
    final Matrix4 m = transformController.value;
    final double scale = GridStateHelper.safeScale(m);
    final double rowExtentOnScreen = cellSize * scale;
    if (rowExtentOnScreen <= 0 || !rowExtentOnScreen.isFinite) return 0;
    return viewportHeight / rowExtentOnScreen;
  }

  double _baseTopYForIndex0({int? colCount, int? firstCol}) {
    if (cellSize <= 0) return 0;
    final int cols = colCount ?? currentColCount;
    final int leftCol = firstCol ?? viewportFirstCol;
    final int baseCell = baseCells[cols] - leftCol;

    final int logicalRowOfIndex0 = _floorDivInt(baseCell, cols);
    final int contentRowOfIndex0 = logicalRowOfIndex0 - baseRow;

    return contentRowOfIndex0 * cellSize;
  }

  int _firstColForTranslation(double tx, double scale, int colCount) {
    if (cellSize <= 0) return 0;
    final double leftX = -tx / scale;
    final int maxFirstCol = max(0, defaultColCount - colCount);
    return (leftX / cellSize).round().clamp(0, maxFirstCol);
  }

  double? _maxTyForBaseTopY(double scale, {int? colCount, int? firstCol}) {
    if (!verticalController.hasClients) return null;
    if (cellSize <= 0) return null;
    final double scrollY = verticalController.offset;
    final double baseTopY = _baseTopYForIndex0(
      colCount: colCount,
      firstCol: firstCol,
    );
    return (scrollY - baseTopY) * scale;
  }

  // =======================================================
  // Auto trigger when scroll near top
  // =======================================================
  void handleInfinitePrepend() {
    if (loadingTop) return;
    if (!verticalController.hasClients) return;
    if (cellSize <= 0) return;
    if (_isContentShortForViewport()) return;

    if (verticalController.offset < 500) {
      loadingTop = true;

      prependVirtualRows(1000);

      Future.delayed(const Duration(milliseconds: 200), () {
        loadingTop = false;
      });
    }
  }

  // =======================================================
  // Prepend rows smoothly
  // =======================================================
  void prependVirtualRows(int count) {
    if (count <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (cellSize <= 0) {
        debugPrint('⚠️ prependVirtualRows skipped: cellSize not ready');
        return;
      }
      if (!verticalController.hasClients) return;
      addRows(count);
      baseRow -= count;
      final addedHeight = count * cellSize;
      verticalController.jumpTo(verticalController.offset + addedHeight);
    });
  }

  bool _isContentShortForViewport() {
    if (!GridStateHelper.isValidCellSize(cellSize)) return false;
    final Size viewport = _viewportSize();
    if (!GridStateHelper.isValidViewport(viewport)) return false;
    final double dataHeight = dataSize().height;
    if (!dataHeight.isFinite) return false;
    return dataHeight <= viewport.height + 0.5;
  }

  void appendVirtualRows(int count) {
    // final addedHeight = count * cellSize;
    // debugPrint('appendVirtualRows');
    // rowCount += count;
    addRows(count);
    onSizeChanged?.call();
  }

  void handleInfiniteAppend() {
    // debugPrint('handleInfiniteAppend');
    if (verticalController.positions.isEmpty) return;
    final position = verticalController.position;
    final double threshold = 500;
    if (position.pixels > position.maxScrollExtent - threshold) {
      appendVirtualRows(1000);
    }
  }

  // =======================================================
  // Dispose
  // =======================================================
  void dispose() {
    verticalController.removeListener(_onVerticalScroll);
    if (_scrollActivityPosition != null && _scrollActivityListener != null) {
      _scrollActivityPosition!.isScrollingNotifier.removeListener(
        _scrollActivityListener!,
      );
    }
    _scrollActivityListener = null;
    _scrollActivityPosition = null;
    verticalController.dispose();
    horizontalController.dispose();
    transformController.removeListener(_handleTransform);
    transformController.dispose();
    scrollOffset.dispose();
    isScalingNotifier.dispose();
    scaleDirectionNotifier.dispose();
    if (_animListener != null) {
      animController.removeListener(_animListener!);
    }
    if (_animStatusListener != null) {
      animController.removeStatusListener(_animStatusListener!);
    }
    animController.dispose();
  }

  int getRowCount([int? colCount]) {
    final int cols = colCount ?? currentColCount;
    return (totalCells / cols).ceil();
  }

  int getDataRowCount([int? colCount]) {
    final int cols = colCount ?? currentColCount;
    if (cols <= 0 || totalDataCells <= 0) return 0;

    final int leftCol = viewportFirstCol.clamp(0, defaultColCount);
    final int firstCol = firstCellCol.clamp(0, defaultColCount);
    final int leadingSlots = (firstCol - leftCol).clamp(0, cols - 1).toInt();

    // Data rows = leading empty slots before index 0 + actual data cells.
    return (totalDataCells + leadingSlots + cols - 1) ~/ cols;
  }

  double gridHeight() {
    return getRowCount() * cellSize;
  }

  void addRows(int rowCount) {
    if (rowCount <= 0) return;
    totalCells += rowCount * currentColCount;
  }

  void removeRows(int rowCount) {
    if (rowCount <= 0) return;
    totalCells -= rowCount * currentColCount;
    if (totalCells < 0) {
      totalCells = 0;
    }
  }

  double getCurrentScale() {
    return transformController.value.getMaxScaleOnAxis();
  }

  // =======================================================
  // Update scroll offset
  // =======================================================
  void _updateOffset() {
    scrollOffset.value = Offset(
      horizontalController.offset,
      verticalController.offset,
    );
    // debugPrint('isScalingNotifier.value ${isScalingNotifier.value}');
    // debugPrint()
    // updateGridPadding();
    // final box = gridKey.currentContext?.findRenderObject() as RenderBox?;
    // if (box == null) return;
    // // final gridPos = box.s;
    // debugPrint("grid top: ${box.size}");
  }

  void updateBaseCell(int newScaleCol) {
    final FocusCell? fc = focusCell;
    if (fc == null) return;
    final int logicalRow = baseRow + fc.row;
    // debugPrint('rowsFromFocalToTop ${rowsFromFocalToTop()}');
    // final int rowsAbove = rowsFromFocalToTop().toInt();
    int index = 0;
    int baseCell = 0;
    index = fc.index;
    // if(index == -1) return;
    if (newScaleCol != currentColCount) {
      // debugPrint('newScaleCol $newScaleCol, currentColCount $currentColCount');
      currentColCount = newScaleCol;
      final Size viewport = _viewportSize();
      // debugPrint('dataSize().height ${dataSize().height}, viewport.height: ${viewport.height}');
      // final double scale = GridStateHelper.safeScale(transformController.value);
      // final dataHeight = (totalDataCells / newScaleCol).ceil() * cellSize * scale;
      // debugPrint('scale $scale, dataHeight $dataHeight, viewport.height ${viewport.height}');
      if (dataSize().height <= viewport.height || index == -1) {
        // int firstColInViewport = getViewportFirstCol();
        baseCells[newScaleCol] = 0;
        // debugPrint('firstColInViewport $firstColInViewport');
      } else {
        baseCell = logicalRow * newScaleCol + fc.col - index;
        baseCells[newScaleCol] = baseCell;
      }
      updateViewportFirstCol();
      // onSizeChanged?.call();
      // updateFirstCellCol(colCount: newScaleCol);
      // int delta = -baseRow - (-baseCell/newScaleCol).ceil();
      // prependVirtualRows(-delta+1);
      // minScrollY = -baseRow * cellSize -
      //   (-baseCell / newScaleCol).ceil() * cellSize;
    }
    // debugPrint(
    //   'newScaleCol $newScaleCol, currentColCount: $currentColCount, baseCell: ${baseCells[newScaleCol]}, index: $index',
    // );
  }

  /// Compute the baseCell so that [index] appears at the current [focusCell]
  /// with the given [scaleCols]. Returns existing [baseCell] if focusCell null.
  int findBaseCell() {
    if (focusCell == null) return 0;
    final int logicalRow = baseRow + focusCell!.row;
    return focusCell!.index - (logicalRow * currentColCount + focusCell!.col);
  }

  void updateFocusCell(Offset point, {bool alreadyScene = false}) {
    final Offset scenePoint = alreadyScene ? point : _viewportToScene(point);
    _lastFocal = scenePoint;
    focusCell = getFocusCell(scenePoint, alreadyScene: true);
  }

  FocusCell getFocusCell(Offset point, {bool alreadyScene = false}) {
    final Offset scene = alreadyScene ? point : _viewportToScene(point);
    final double gridX = scene.dx + scrollOffset.value.dx;
    final double gridY = scene.dy + scrollOffset.value.dy;

    int col = gridX ~/ cellSize;
    int row = gridY ~/ cellSize;
    final int logicalRow = row + baseRow;
    int index = logicalRow * currentColCount + col - baseCells[currentColCount];

    // if(index > totalDataCells - 1){
    //   row = -baseRow + (totalDataCells/currentColCount).ceil() - 1;
    //   col = 4 - totalDataCells % currentColCount;
    //   index = totalDataCells-1;
    // }
    // debugPrint('row $row');
    // if(index > totalDataCells - 1){
    //   // row = -baseRow;
    //   row = row;
    //   col = col;
    //   // index = -1;
    // }

    return FocusCell(
      row: row,
      col: col,
      colCount: currentColCount,
      index: index,
    );
  }

  /// Distance in rows from the focused cell's top edge to the viewport's top edge.
  /// Uses scroll position for accuracy (no floor).
  double rowsFromFocalToTop() {
    if (focusCell == null || cellSize <= 0) return 0;

    final double scrollY = scrollOffset.value.dy;
    final double cellTop = focusCell!.row * cellSize;
    final double rows = (cellTop - scrollY) / cellSize;

    if (rows.isNaN || rows.isInfinite) return 0;
    return rows < 0 ? 0 : rows;
  }

  // Convert viewport coordinates → scene coordinates (pre-scroll) using current transform
  Offset _viewportToScene(Offset viewportPoint) {
    final Matrix4 m = transformController.value;
    final double scale = m.getMaxScaleOnAxis().clamp(0.0001, 1000.0);
    final double tx = m.storage[12];
    final double ty = m.storage[13];
    return Offset(
      (viewportPoint.dx - tx) / scale,
      (viewportPoint.dy - ty) / scale,
    );
  }

  Future<void> animateScaleTo(double targetScale, int targetScaleCol) async {
    // Guard: need layout to be ready
    // debugPrint(
    //   'animateScaleTo: targetScale $targetScale, targetScaleCol $targetScaleCol',
    // );
    final Size viewportSize = _viewportSize();
    if (viewportSize.isEmpty) return;

    final Matrix4 currentMatrix = transformController.value.clone();
    final double currentScale = currentMatrix.getMaxScaleOnAxis();
    final double clampedTarget = targetScale.clamp(1.0, 5.0).toDouble();

    // If nothing to change, skip
    if ((currentScale - clampedTarget).abs() < 0.01) return;

    // Choose focal in scene space (keeps where the fingers were)
    final Offset focalScene =
        _lastFocal ?? _sceneCenter(viewportSize, currentMatrix);

    final Size gridSize = _gridSize();

    final double currentTx = currentMatrix.storage[12];
    final double currentTy = currentMatrix.storage[13];

    final Offset targetTranslation = _translationKeepFocal(
      focal: focalScene,
      currentScale: currentScale,
      targetScale: clampedTarget,
      currentTranslation: Offset(currentTx, currentTy),
      viewport: viewportSize,
      grid: gridSize,
      targetScaleCol: targetScaleCol,
    );

    final future = _startScaleAnimation(
      beginScale: currentScale,
      beginTranslation: Offset(
        currentMatrix.storage[12],
        currentMatrix.storage[13],
      ),
      endScale: clampedTarget,
      endTranslation: targetTranslation,
      viewport: viewportSize,
      grid: gridSize,
      targetScaleCol: targetScaleCol,
    );

    try {
      await future.orCancel;
    } on TickerCanceled {
      // Animation was canceled (e.g. widget disposed). Safe to ignore.
    }
  }

  // =======================================================
  // Helpers
  // =======================================================
  Size _viewportSize() {
    if (GridStateHelper.isValidViewport(_cachedViewportSize)) {
      return _cachedViewportSize;
    }
    final renderBox =
        containerKey.currentContext?.findRenderObject() as RenderBox?;
    final Size size = renderBox?.size ?? Size.zero;
    if (GridStateHelper.isValidViewport(size)) {
      _cachedViewportSize = size;
    }
    return size;
  }

  Size _gridSize() {
    // final renderBox = gridKey.currentContext?.findRenderObject() as RenderBox?;
    // if (renderBox != null) return renderBox.size;
    // debugPrint('_gridSize colCount: $colCount, rowCount: $rowCount, height: ${rowCount * cellSize}');
    return Size(defaultColCount * cellSize, rowCount * cellSize);
  }

  Offset _sceneCenter(Size viewport, Matrix4 matrix) {
    final double scale = matrix.getMaxScaleOnAxis();
    if (scale == 0) return Offset.zero;
    final double tx = matrix.storage[12];
    final double ty = matrix.storage[13];
    return Offset(
      (viewport.width / 2 - tx) / scale,
      (viewport.height / 2 - ty) / scale,
    );
  }

  Offset _translationKeepFocal({
    required Offset focal,
    required double currentScale,
    required double targetScale,
    required Offset currentTranslation,
    required Size viewport,
    required Size grid,
    required int targetScaleCol,
  }) {
    // Keep the focal point at the same viewport position after scaling
    double tx = currentTranslation.dx + (currentScale - targetScale) * focal.dx;
    double ty = currentTranslation.dy + (currentScale - targetScale) * focal.dy;

    // Clamp so grid edges never expose background
    final double minTx = max(
      viewport.width - grid.width * targetScale,
      viewport.width * (1 - targetScale),
    );
    const double maxTx = 0.0;
    double minTy = max(
      viewport.height - grid.height * targetScale,
      viewport.height * (1 - targetScale),
    );
    double maxTy = 0.0;

    // final int firstCol = _firstColForTranslation(
    //   tx,
    //   targetScale,
    //   targetScaleCol,
    // );
    // final double? baseLimit = _maxTyForBaseTopY(
    //   targetScale,
    //   colCount: targetScaleCol,
    //   firstCol: firstCol,
    // );
    // if (baseLimit != null) {
    //   maxTy = min(maxTy, baseLimit);
    // }
    // minTy = min(minTy, minScrollY);

    double minTxSafe = minTx;
    double maxTxSafe = maxTx;
    if (minTxSafe > maxTxSafe) {
      final double tmp = minTxSafe;
      minTxSafe = maxTxSafe;
      maxTxSafe = tmp;
    }
    tx = tx.clamp(minTxSafe, maxTxSafe);

    double minTySafe = minTy;
    double maxTySafe = maxTy;
    if (minTySafe > maxTySafe) {
      final double tmp = minTySafe;
      minTySafe = maxTySafe;
      maxTySafe = tmp;
    }
    // ty = ty.clamp(minTySafe, maxTySafe);

    return Offset(tx, ty);
  }

  TickerFuture _startScaleAnimation({
    required double beginScale,
    required Offset beginTranslation,
    required double endScale,
    required Offset endTranslation,
    required Size viewport,
    required Size grid,
    int? targetScaleCol,
  }) {
    // updateBaseCell(targetColCount);
    clampScrollToFirstCellWhenContentShort();
    // debugPrint('_startScaleAnimation');
    animController.stop();
    if (_animListener != null) {
      animController.removeListener(_animListener!);
    }

    // Snap horizontal target to nearest allowed column offset (discrete steps)
    // 3 cols: snap viewport-left x to 0,1,2 cols
    // 1 col: tx can be 0, -1col, -2col, -3col, -4col; choose nearest
    final int snapCol = targetScaleCol ?? currentColCount;
    if (snapCol == 3) {
      final double scale = endScale;
      final double tx = endTranslation.dx;

      // World X at viewport's left edge
      double leftX = -tx / scale;
      // Snap to nearest column boundary then clamp to [0, 2 * cellSize]
      leftX = (leftX / cellSize).round() * cellSize;
      leftX = leftX.clamp(0.0, 2 * cellSize);

      // Convert back to translation
      double snappedTx = -leftX * scale;

      // Clamp translation to avoid exposing background
      final double minTx = max(
        viewport.width - grid.width * scale,
        viewport.width * (1 - scale),
      );
      const double maxTx = 0.0;
      snappedTx = snappedTx.clamp(minTx, maxTx);

      endTranslation = Offset(snappedTx, endTranslation.dy);
    } else if (snapCol == 1) {
      final double scale = endScale;
      final double tx = endTranslation.dx;

      // World X at viewport's left edge
      double leftX = -tx / scale;
      // Snap to nearest column boundary then clamp to [0, 4 * cellSize]
      leftX = (leftX / cellSize).round() * cellSize;
      leftX = leftX.clamp(0.0, 4 * cellSize);

      // Convert back to translation
      double snappedTx = -leftX * scale;

      // Clamp translation to avoid exposing background
      final double minTx = max(
        viewport.width - grid.width * scale,
        viewport.width * (1 - scale),
      );
      const double maxTx = 0.0;
      snappedTx = snappedTx.clamp(minTx, maxTx);

      endTranslation = Offset(snappedTx, endTranslation.dy);
    }

    final curved = CurvedAnimation(
      parent: animController,
      curve: Curves.easeOutCubic,
    );

    _scaleAnim = Tween<double>(
      begin: beginScale,
      end: endScale,
    ).animate(curved);
    _translateAnim = Tween<Offset>(
      begin: beginTranslation,
      end: endTranslation,
    ).animate(curved);

    void tick() {
      // jumpToFirstDataRow();
      // updateBaseCell(targetColCount);
      // clampScrollToFirstCellWhenContentShort();
      // debugPrint('clampScrollToFirstCellWhenContentShort');
      _clampScrollToDataEnd();
      final double scale = _scaleAnim?.value ?? beginScale;
      final Offset tr = _translateAnim?.value ?? beginTranslation;

      double tx = tr.dx;
      double ty = tr.dy;

      final double minTx = max(
        viewport.width - grid.width * scale,
        viewport.width * (1 - scale),
      );
      const double maxTx = 0.0;
      final double minTy = max(
        viewport.height - grid.height * scale,
        viewport.height * (1 - scale),
      );
      double maxTy = 0.0;
      final int effectiveCols = targetScaleCol ?? currentColCount;
      final int firstCol = _firstColForTranslation(tx, scale, effectiveCols);
      final double? baseLimit = _maxTyForBaseTopY(
        scale,
        colCount: effectiveCols,
        firstCol: firstCol,
      );
      if (baseLimit != null) {
        maxTy = min(maxTy, baseLimit);
      }

      double minTxSafe = minTx;
      double maxTxSafe = maxTx;
      if (minTxSafe > maxTxSafe) {
        final double tmp = minTxSafe;
        minTxSafe = maxTxSafe;
        maxTxSafe = tmp;
      }
      tx = tx.clamp(minTxSafe, maxTxSafe);

      double minTySafe = minTy;
      double maxTySafe = maxTy;
      if (minTySafe > maxTySafe) {
        final double tmp = minTySafe;
        minTySafe = maxTySafe;
        maxTySafe = tmp;
      }
      ty = ty.clamp(minTySafe, maxTySafe);

      transformController.value = Matrix4.identity()
        ..translateByDouble(tx, ty, 0.0, 1.0)
        ..scaleByDouble(scale, scale, 1.0, 1.0);
    }

    _animListener = tick;
    if (_animStatusListener != null) {
      animController.removeStatusListener(_animStatusListener!);
    }
    void statusListener(AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        updateViewportFirstCol();
        clampScrollToFirstCellWhenContentShort();
      }
    }

    _animStatusListener = statusListener;
    animController
      ..addListener(tick)
      ..addStatusListener(statusListener);
    return animController.forward(from: 0);
  }

  void jumpToLogicalRow(int logicalRow) {
    _jumpToLogicalRowDouble(logicalRow.toDouble());
  }

  void jumpToRealTopRow(double realTopRow, {int? colCount, int? leftCol}) {
    final int logicalDataStart = logicalRowOfDataStart(
      colCount: colCount,
      leftCol: leftCol,
    );
    _jumpToLogicalRowDouble(logicalDataStart + realTopRow);
  }

  /// Returns true when [dataIndex] currently maps to a visible grid row.
  bool isDataIndexInViewport(int dataIndex, {double rowEpsilon = 0.01}) {
    if (dataIndex < 0 || dataIndex >= totalDataCells) return false;
    if (!verticalController.hasClients || cellSize <= 0) return false;

    final int cols = currentColCount <= 0 ? 1 : currentColCount;
    updateViewportFirstCol();
    final int maxFirstCol = max(0, defaultColCount - cols);
    final int leftCol = viewportFirstCol.clamp(0, maxFirstCol);
    final int firstCol = firstCellCol.clamp(0, defaultColCount);
    final int leadingSlots = (firstCol - leftCol).clamp(0, cols - 1).toInt();
    final int targetRealRow = (leadingSlots + dataIndex) ~/ cols;

    final double viewportHeight =
        (_cachedViewportSize.height.isFinite && _cachedViewportSize.height > 0)
        ? _cachedViewportSize.height
        : verticalController.position.viewportDimension;
    if (!viewportHeight.isFinite || viewportHeight <= 0) return false;

    final double visibleRows = visibleDataRowsInViewport(viewportHeight);
    if (!visibleRows.isFinite || visibleRows <= 0) return false;

    final double currentTopRealRow = currentRealTopRow(
      colCount: cols,
      leftCol: leftCol,
    );
    if (!currentTopRealRow.isFinite) return false;

    final double minVisibleRow = currentTopRealRow - rowEpsilon;
    final double maxVisibleRow =
        currentTopRealRow + visibleRows - 1.0 + rowEpsilon;
    return targetRealRow >= minVisibleRow && targetRealRow <= maxVisibleRow;
  }

  /// Keep [dataIndex] in viewport with hysteresis to avoid frequent jumps.
  /// Returns true only when a jump is actually applied.
  bool ensureDataIndexVisible(
    int dataIndex, {
    double alignInViewport = 0.45,
    double hysteresisRows = 1.0,
  }) {
    if (dataIndex < 0 || dataIndex >= totalDataCells) return false;
    if (!verticalController.hasClients || cellSize <= 0) return false;

    final int cols = currentColCount <= 0 ? 1 : currentColCount;
    updateViewportFirstCol();
    final int maxFirstCol = max(0, defaultColCount - cols);
    final int leftCol = viewportFirstCol.clamp(0, maxFirstCol);
    final int firstCol = firstCellCol.clamp(0, defaultColCount);
    final int leadingSlots = (firstCol - leftCol).clamp(0, cols - 1).toInt();
    final int targetRealRow = (leadingSlots + dataIndex) ~/ cols;

    final double viewportHeight =
        (_cachedViewportSize.height.isFinite && _cachedViewportSize.height > 0)
        ? _cachedViewportSize.height
        : verticalController.position.viewportDimension;
    if (!viewportHeight.isFinite || viewportHeight <= 0) return false;

    final double visibleRows = visibleDataRowsInViewport(viewportHeight);
    if (!visibleRows.isFinite || visibleRows <= 0) return false;

    final double currentTopRealRow = currentRealTopRow(
      colCount: cols,
      leftCol: leftCol,
    );
    if (!currentTopRealRow.isFinite) return false;

    final double maxHysteresis = ((visibleRows - 1.0) / 2.0).clamp(0.0, 1000.0);
    final double effectiveHysteresis = hysteresisRows
        .clamp(0.0, maxHysteresis)
        .toDouble();
    final double minAcceptableRow = currentTopRealRow + effectiveHysteresis;
    final double maxAcceptableRow =
        currentTopRealRow + visibleRows - 1.0 - effectiveHysteresis;
    if (targetRealRow >= minAcceptableRow &&
        targetRealRow <= maxAcceptableRow) {
      return false;
    }

    final double clampedAlign = alignInViewport.clamp(0.0, 1.0).toDouble();
    final double desiredTopRow =
        targetRealRow - ((visibleRows - 1.0) * clampedAlign);
    final double maxTopRow = max(
      0.0,
      realDataRowCount(colCount: cols).toDouble() - visibleRows,
    );
    final double clampedTopRow = desiredTopRow.clamp(0.0, maxTopRow);
    if (!clampedTopRow.isFinite) return false;
    if ((clampedTopRow - currentTopRealRow).abs() < 0.25) return false;

    jumpToRealTopRow(clampedTopRow, colCount: cols, leftCol: leftCol);
    return true;
  }

  void _jumpToLogicalRowDouble(double logicalRow) {
    if (!verticalController.hasClients || cellSize <= 0) return;
    final Matrix4 m = transformController.value;
    final double scale = GridStateHelper.safeScale(m);
    final double ty = GridStateHelper.translateY(m);

    final double rowTop = (logicalRow - baseRow) * cellSize;
    final double target = GridStateHelper.clampToScrollExtents(
      value: rowTop + (ty / scale),
      position: verticalController.position,
    );

    final double current = verticalController.offset;
    if ((target - current).abs() < 0.35) {
      return;
    }
    verticalController.jumpTo(target);
  }

  /// Quick dump of key grid numbers in table form for debugging.
  void debugPrintTable() {
    final double scale = transformController.value.getMaxScaleOnAxis().clamp(
      0.0001,
      1000.0,
    );
    final Matrix4 m = transformController.value;
    final double tx = m.storage[12];
    final double ty = m.storage[13];
    final double scaleX = m.storage[0];
    final double scaleY = m.storage[5];
    final double scrollY = verticalController.hasClients
        ? verticalController.offset
        : 0.0;

    final entries = <List<String>>[
      ['currentColCount', '$currentColCount'],
      ['scaleDirection', '$scaleDirection'],
      ['firstCellCol', '$firstCellCol'],
      ['viewportFirstCol', '$viewportFirstCol'],
      ['baseRow', '$baseRow'],
      ['baseCells', baseCells.join(', ')],
      ['totalDataCells', '$totalDataCells'],
      ['totalCells', '$totalCells'],
      ['rowCount', '$rowCount'],
      ['dataRowCount', '${getDataRowCount()}'],
      ['cellSize', cellSize.toStringAsFixed(2)],
      ['scrollY', scrollY.toStringAsFixed(2)],
      ['scale', scale.toStringAsFixed(3)],
      ['scaleX', scaleX.toStringAsFixed(3)],
      ['scaleY', scaleY.toStringAsFixed(3)],
      ['tx', tx.toStringAsFixed(2)],
      ['ty', ty.toStringAsFixed(2)],
      ['baseTopY', '${_baseTopYForIndex0()}'],
      ['focusCell', '${focusCell!.index}'],
    ];

    final int keyWidth = entries
        .map((r) => r[0].length)
        .fold(0, (a, b) => a > b ? a : b);
    final int valWidth = entries
        .map((r) => r[1].length)
        .fold(0, (a, b) => a > b ? a : b);

    String border() =>
        '+${'-' * (keyWidth + 2)}+${'-' * (valWidth + 2)}'
        '+${'-' * (keyWidth + 2)}+${'-' * (valWidth + 2)}'
        '+${'-' * (keyWidth + 2)}+${'-' * (valWidth + 2)}+';

    final buffer = StringBuffer()..writeln(border());
    for (int i = 0; i < entries.length; i += 3) {
      final c1 = entries[i];
      final c2 = i + 1 < entries.length ? entries[i + 1] : const ['', ''];
      final c3 = i + 2 < entries.length ? entries[i + 2] : const ['', ''];
      buffer.writeln(
        '| ${c1[0].padRight(keyWidth)} | ${c1[1].padRight(valWidth)} '
        '| ${c2[0].padRight(keyWidth)} | ${c2[1].padRight(valWidth)} '
        '| ${c3[0].padRight(keyWidth)} | ${c3[1].padRight(valWidth)} |',
      );
      buffer.writeln(border());
    }
    debugPrint(buffer.toString());
  }

  // =======================================================
  // Visible window calculation
  // =======================================================
  GridWindow getVisibleWindow(
    double viewportWidth,
    double viewportHeight, {
    int extraRowsAhead = 0,
    int extraRowsBehind = 0,
    int extraColsAhead = 0,
    int extraColsBehind = 0,
  }) {
    // Safety guard: avoid NaN/Infinity when layout not ready
    if (cellSize.isNaN ||
        cellSize.isInfinite ||
        cellSize <= 0 ||
        viewportWidth.isNaN ||
        viewportWidth.isInfinite ||
        viewportHeight.isNaN ||
        viewportHeight.isInfinite) {
      return GridWindow(firstRow: 0, firstCol: 0, lastRow: 0, lastCol: 0);
    }
    // final double currentScale = transformController.value.getMaxScaleOnAxis();
    // final double newCellSize = cellSize * currentScale;
    final scrollX = scrollOffset.value.dx;
    final scrollY = scrollOffset.value.dy;

    int firstCol = max(0, (scrollX / cellSize).floor() - extraColsBehind);
    int firstRow = max(0, (scrollY / cellSize).floor() - extraRowsBehind);

    final visibleCols =
        (viewportWidth / cellSize).ceil() +
        2 +
        extraColsBehind +
        extraColsAhead;
    final visibleRows =
        (viewportHeight / cellSize).ceil() +
        2 +
        extraRowsBehind +
        extraRowsAhead;

    final lastCol = min(defaultColCount, firstCol + visibleCols);
    final lastRow = min(rowCount, firstRow + visibleRows);

    return GridWindow(
      firstRow: firstRow,
      firstCol: firstCol,
      lastRow: lastRow,
      lastCol: lastCol,
    );
  }
}
