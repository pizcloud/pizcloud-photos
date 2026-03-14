import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:pizcloud_gallery/grid/media_item.dart';

import 'viewer_session.dart';
import 'viewer_state.dart';

class ViewerController extends ChangeNotifier {
  ViewerController({required ViewerSession session})
    : _items = List<MediaItem>.from(session.items),
      _state = ViewerState(
        currentIndex: session.clampedInitialIndex,
        totalCount: session.items.length,
      ),
      pageController = PageController(
        initialPage: session.clampedInitialIndex,
      ) {
    _itemsView = UnmodifiableListView<MediaItem>(_items);
  }

  final PageController pageController;
  final List<MediaItem> _items;
  late final UnmodifiableListView<MediaItem> _itemsView;
  ViewerState _state;

  ViewerState get state => _state;
  List<MediaItem> get items => _itemsView;
  int get totalCount => _state.totalCount;
  int get currentIndex => _state.currentIndex;
  MediaItem? get currentItem =>
      _items.isEmpty ? null : _items[_state.currentIndex];

  void onPageChanged(int nextIndex) {
    if (nextIndex == _state.currentIndex) return;
    if (nextIndex < 0 || nextIndex >= _state.totalCount) return;
    _state = _state.copyWith(currentIndex: nextIndex);
    notifyListeners();
  }

  Future<void> animateToIndex(int nextIndex) async {
    if (nextIndex < 0 || nextIndex >= _state.totalCount) return;
    await pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  ViewerDeleteResult? removeCurrentItem() {
    if (_items.isEmpty) {
      return null;
    }
    final int removedIndex = _state.currentIndex;
    final MediaItem removedItem = _items.removeAt(removedIndex);
    final int nextTotal = _items.length;
    if (nextTotal <= 0) {
      _state = _state.copyWith(currentIndex: 0, totalCount: 0);
      notifyListeners();
      return ViewerDeleteResult(
        removedItem: removedItem,
        currentIndex: 0,
        totalCount: 0,
      );
    }
    final int nextIndex = removedIndex.clamp(0, nextTotal - 1);
    _state = _state.copyWith(currentIndex: nextIndex, totalCount: nextTotal);
    if (pageController.hasClients && nextIndex != removedIndex) {
      pageController.jumpToPage(nextIndex);
    }
    notifyListeners();
    return ViewerDeleteResult(
      removedItem: removedItem,
      currentIndex: nextIndex,
      totalCount: nextTotal,
    );
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }
}

class ViewerDeleteResult {
  const ViewerDeleteResult({
    required this.removedItem,
    required this.currentIndex,
    required this.totalCount,
  });

  final MediaItem removedItem;
  final int currentIndex;
  final int totalCount;

  bool get isEmpty => totalCount <= 0;
}
