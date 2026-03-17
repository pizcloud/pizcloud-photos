import 'media_item.dart';
import 'storage_indicator.dart'; // new

class CellData {
  final String id;
  final String text;
  final int? dataIndex;
  final MediaItem? mediaItem;
  final int? thumbEdge;
  final String? thumbUrl;
  final double renderScale;
  final int? currentColCount;
  final int? targetColCount;
  final bool preferTargetColCount;
  final GridStorageIndicatorState? storageIndicatorState; // new

  CellData({
    required this.id,
    required this.text,
    this.dataIndex,
    this.mediaItem,
    this.thumbEdge,
    this.thumbUrl,
    this.renderScale = 1.0,
    this.currentColCount,
    this.targetColCount,
    this.preferTargetColCount = true,
    this.storageIndicatorState, // new
  });

  bool sameVisual(CellData other) {
    // return thumbEdge == other.thumbEdge;
    return id == other.id &&
        text == other.text &&
        dataIndex == other.dataIndex &&
        mediaItem?.id == other.mediaItem?.id &&
        thumbEdge == other.thumbEdge &&
        thumbUrl == other.thumbUrl &&
        currentColCount == other.currentColCount &&
        targetColCount == other.targetColCount &&
        preferTargetColCount == other.preferTargetColCount &&
        storageIndicatorState == other.storageIndicatorState; // new
  }
}
