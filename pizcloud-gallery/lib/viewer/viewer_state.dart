class ViewerState {
  const ViewerState({
    required this.currentIndex,
    required this.totalCount,
  });

  final int currentIndex;
  final int totalCount;

  bool get hasPrev => currentIndex > 0;
  bool get hasNext => currentIndex + 1 < totalCount;

  ViewerState copyWith({
    int? currentIndex,
    int? totalCount,
  }) {
    return ViewerState(
      currentIndex: currentIndex ?? this.currentIndex,
      totalCount: totalCount ?? this.totalCount,
    );
  }
}
