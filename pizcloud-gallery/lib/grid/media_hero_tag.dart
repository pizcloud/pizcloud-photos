String mediaViewerHeroTag(String mediaId) => 'media_viewer_$mediaId';

String mediaGridCellHeroTag({required String mediaId, required String cellId}) {
  // Use a stable per-media hero tag so viewer can match after page swipes.
  return mediaViewerHeroTag(mediaId);
}
