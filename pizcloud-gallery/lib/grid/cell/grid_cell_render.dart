part of '../grid_cell.dart';

extension _GridCellStateRender on _GridCellState {
  Widget _buildListenableMedia(MediaItem media, GridAppearancePalette palette) {
    if (media.isLocal) {
      final String? cacheKey = _resolveLocalThumbCacheKey(media);
      if (cacheKey == null || cacheKey.isEmpty) {
        return _buildMediaCell(media, palette);
      }
      return ValueListenableBuilder<int>(
        valueListenable: widget.bytesCache.listenableOf(cacheKey),
        builder: (context, tick, child) => _buildMediaCell(media, palette),
      );
    }
    final String? thumbUrl = widget.data.thumbUrl;
    if (thumbUrl == null) {
      return _buildMediaCell(media, palette);
    }
    return ValueListenableBuilder<int>(
      valueListenable: widget.bytesCache.listenableOf(thumbUrl),
      builder: (context, tick, child) => _buildMediaCell(media, palette),
    );
  }

  Widget _buildFallback(GridAppearancePalette palette) {
    return Center(
      child: Text(
        widget.data.text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: palette.placeholderText,
        ),
      ),
    );
  }

  Widget _buildMediaCell(MediaItem media, GridAppearancePalette palette) {
    if (media.isLocal) {
      return _buildLocalMediaCell(media, palette);
    }

    final Uint8List? prefetchedBytes = _readPrefetchedBytes();
    if (prefetchedBytes != null) {
      return _buildMediaStack(
        media: media,
        palette: palette,
        image: Image.memory(
          prefetchedBytes,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
        ),
      );
    }

    final ImageProvider<Object>? provider = _shownProvider;
    return _buildMediaStack(
      media: media,
      palette: palette,
      image: provider == null
          ? _buildVideoAwareFallback(media, palette)
          : Image(
              image: provider,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.none,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => media.isVideo
                  ? _buildVideoAwareFallback(media, palette)
                  : Container(color: palette.cellErrorBackground),
            ),
    );
  }

  Uint8List? _readPrefetchedBytes() {
    final String? thumbUrl = widget.data.thumbUrl;
    if (thumbUrl == null) return null;
    return widget.bytesCache.peek(thumbUrl);
  }

  Widget _buildBadge(String text, GridAppearancePalette palette) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.indexBadgeBackground,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          text,
          style: TextStyle(
            color: palette.indexBadgeText,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _buildLocalMediaCell(MediaItem media, GridAppearancePalette palette) {
    final ({String key, Uint8List bytes})? prefetched =
        _readLocalPrefetchedBytes(media);
    if (prefetched != null) {
      _rememberLocalCellFrame(key: prefetched.key, bytes: prefetched.bytes);
      return _buildMediaStack(
        media: media,
        palette: palette,
        image: _buildLocalThumbImage(
          bytes: prefetched.bytes,
          thumbKey: prefetched.key,
        ),
      );
    }

    final ImageProvider<Object>? provider = _shownProvider;
    if (provider != null) {
      return _buildMediaStack(
        media: media,
        palette: palette,
        image: Image(
          image: provider,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => media.isVideo
              ? _buildVideoAwareFallback(media, palette)
              : Container(color: palette.cellErrorBackground),
        ),
      );
    }

    final Widget? waitingImage = _buildHeldLocalFrameImage();
    if (waitingImage != null) {
      return _buildMediaStack(
        media: media,
        palette: palette,
        image: waitingImage,
      );
    }

    return _buildMediaStack(
      media: media,
      palette: palette,
      image: _buildLocalWaitingFallback(media, palette),
    );
  }

  ({String key, Uint8List bytes})? _readLocalPrefetchedBytes(MediaItem media) {
    final String? cacheKey = _resolveLocalThumbCacheKey(media);
    if (cacheKey == null || cacheKey.isEmpty) {
      _reportLocalCacheLookup(hit: false, fromRenderStage: true, key: cacheKey);
      return null;
    }
    final Uint8List? bytes = widget.bytesCache.peek(cacheKey);
    if (bytes == null || bytes.isEmpty) {
      _reportLocalCacheLookup(hit: false, fromRenderStage: true, key: cacheKey);
      return null;
    }
    _reportLocalCacheLookup(hit: true, fromRenderStage: true, key: cacheKey);
    return (key: cacheKey, bytes: bytes);
  }

  String? _resolveLocalThumbCacheKey(MediaItem media) {
    final String source =
        (widget.data.thumbUrl ??
                media.previewUrl ??
                media.localPath ??
                media.originalUrl)
            .trim();
    if (source.isEmpty) {
      return null;
    }
    return LocalDeviceMediaUri.buildTypedThumbCacheKey(
      source,
      isVideo: media.isVideo,
    );
  }

  void _rememberLocalCellFrame({
    required String key,
    required Uint8List bytes,
  }) {
    if (key.isEmpty || bytes.isEmpty) {
      return;
    }
    _lastShownLocalFrameKey = key;
    _lastShownLocalFrameBytes = bytes;
  }

  Widget? _buildHeldLocalFrameImage() {
    final String? key = _lastShownLocalFrameKey;
    final Uint8List? bytes = _lastShownLocalFrameBytes;
    if (key == null || bytes == null || bytes.isEmpty) {
      return null;
    }
    return _buildLocalThumbImage(bytes: bytes, thumbKey: key);
  }

  Widget _buildLocalThumbImage({
    required Uint8List bytes,
    required String thumbKey,
  }) {
    return Image.memory(
      bytes,
      key: ValueKey<String>('local_thumb_$thumbKey'),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.none,
      gaplessPlayback: true,
    );
  }

  Widget _buildMediaStack({
    required MediaItem media,
    required GridAppearancePalette palette,
    required Widget image,
  }) {
    final GridStorageIndicatorState? storageIndicatorState =
        widget.data.storageIndicatorState; // new
    final bool isSelected = widget.data.isSelected; // new
    final Color selectedAccent = palette.brightness == Brightness.dark
        ? const Color(0xFF8AB4FF)
        : const Color(0xFF2563EB); // new
    final double safeViewScale = _resolveSafeViewScale(); // new
    final double inverseViewScale = 1.0 / safeViewScale; // new
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        // new
        // if (isSelected) Positioned(left: 6, top: 6, child: Icon(Icons.check_circle_rounded)); // old
        if (isSelected)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.24),
                border: Border.all(
                  color: selectedAccent.withValues(alpha: 0.92),
                  width: 2.2,
                ),
              ),
            ),
          ),
        if (isSelected)
          Positioned(
            right: 6,
            top: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selectedAccent,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 1.1,
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    blurRadius: 6.0,
                    color: Color.fromRGBO(0, 0, 0, 0.45),
                    offset: Offset(0.0, 0.0),
                  ),
                ],
              ),
              child: const Padding(
                padding: EdgeInsets.all(2.2),
                child: Icon(Icons.check_rounded, size: 14, color: Colors.white),
              ),
            ),
          ),
        if (storageIndicatorState != null)
          // old
          // Positioned(
          //   right: 4,
          //   // Keep distance when the video duration chip is present.
          //   bottom: media.isVideo ? 24 : 4,
          //   child: _buildStorageIndicatorIcon(storageIndicatorState, palette),
          // ),
          Positioned(
            right: 4 * inverseViewScale,
            // Keep distance when the video duration chip is present.
            bottom: (media.isVideo ? 24 : 4) * inverseViewScale,
            child: Transform.scale(
              scale: inverseViewScale,
              alignment: Alignment.bottomRight,
              child: _buildStorageIndicatorIcon(storageIndicatorState, palette),
            ),
          ),
        // #new
        if (media.isVideo)
          Positioned(
            right: 4,
            bottom: 4,
            child: _buildVideoMetaChip(media, palette),
          ),
        if (GridCell._showIndexBadge)
          Positioned(
            left: 4,
            bottom: 4,
            child: _buildBadge(widget.data.text, palette),
          ),
      ],
    );
  }

  // new
  Widget _buildStorageIndicatorIcon(
    GridStorageIndicatorState state,
    GridAppearancePalette palette,
  ) {
    final IconData icon = switch (state) {
      GridStorageIndicatorState.local => Icons.cloud_off_outlined,
      GridStorageIndicatorState.remote => Icons.cloud_outlined,
      GridStorageIndicatorState.merged => Icons.cloud_done_outlined,
    };
    return Icon(
      icon,
      size: 16,
      color: palette.mediaOverlayIcon.withValues(alpha: 0.88),
      shadows: const <Shadow>[
        Shadow(
          blurRadius: 5.0,
          color: Color.fromRGBO(0, 0, 0, 0.6),
          offset: Offset(0.0, 0.0),
        ),
      ],
    );
  }

  double _resolveSafeViewScale() {
    final double scale = widget.viewScale;
    if (scale.isNaN || scale.isInfinite || scale <= 0) {
      return 1.0;
    }
    // Grid minScale is 1; clamp defensively to avoid enlarging the icon.
    return scale < 1.0 ? 1.0 : scale;
  }
  // #new

  Widget _buildVideoAwareFallback(
    MediaItem media,
    GridAppearancePalette palette,
  ) {
    if (!media.isVideo) {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            palette.cellBackground.withValues(alpha: 0.92),
            palette.cellBackground.withValues(alpha: 1.0),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.play_circle_fill_rounded,
          color: palette.mediaOverlayIcon.withValues(alpha: 0.78),
          size: 24,
        ),
      ),
    );
  }

  Widget _buildLocalWaitingFallback(
    MediaItem media,
    GridAppearancePalette palette,
  ) {
    if (media.isVideo) {
      return _buildVideoAwareFallback(media, palette);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            palette.cellBackground.withValues(alpha: 0.94),
            palette.cellBackground.withValues(alpha: 1.0),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoMetaChip(MediaItem media, GridAppearancePalette palette) {
    final String? durationText = _formatVideoDuration(media.duration);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.indexBadgeBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_arrow_rounded,
              color: palette.mediaOverlayIcon,
              size: 12,
            ),
            if (durationText != null) const SizedBox(width: 2),
            if (durationText != null)
              Text(
                durationText,
                style: TextStyle(
                  color: palette.indexBadgeText,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String? _formatVideoDuration(Duration? duration) {
    if (duration == null) {
      return null;
    }
    final int totalSeconds = duration.inSeconds;
    if (totalSeconds <= 0) {
      return null;
    }
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
