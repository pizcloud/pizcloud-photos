class GridWindow {
  final int firstRow;
  final int firstCol;
  final int lastRow;
  final int lastCol;

  const GridWindow({
    required this.firstRow,
    required this.firstCol,
    required this.lastRow,
    required this.lastCol,
  });

  double get centerRow {
    if (lastRow <= firstRow) return firstRow.toDouble();
    return (firstRow + lastRow - 1) / 2.0;
  }

  double get centerCol {
    if (lastCol <= firstCol) return firstCol.toDouble();
    return (firstCol + lastCol - 1) / 2.0;
  }

  bool sameAs(GridWindow other) {
    return firstRow == other.firstRow &&
        firstCol == other.firstCol &&
        lastRow == other.lastRow &&
        lastCol == other.lastCol;
  }

  @override
  String toString() {
    return 'GridWindow('
        'firstRow: $firstRow, '
        'firstCol: $firstCol, '
        'lastRow: $lastRow, '
        'lastCol: $lastCol'
        ')';
  }
}
