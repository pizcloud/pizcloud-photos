// ignore_for_file: invalid_use_of_protected_member

part of 'viewer_image_loader.dart';

extension _ViewerImageLoaderVideoPart on _ViewerImageLoaderState {
  Future<void> _prepareVideoController() async {
    final int token = ++_videoRequestToken;
    final VideoPlayerController? previous = _videoController;
    _detachVideoValueListener();
    widget.onVideoControllerChanged?.call(null);
    if (mounted) {
      setState(() {
        _videoController = null;
        _videoReady = false;
        _videoError = null;
        _videoWidth = null;
        _videoHeight = null;
      });
    } else {
      _videoController = null;
      _videoReady = false;
      _videoError = null;
      _videoWidth = null;
      _videoHeight = null;
    }
    if (previous != null) {
      _safeDisposeVideoController(previous);
    }

    final VideoPlayerController? resolved = await _resolveVideoController(
      widget.item.originalUrl.trim(),
    );
    if (resolved == null) {
      if (!mounted || token != _videoRequestToken) return;
      setState(() {
        _videoReady = false;
        _videoError = StateError('Video source is not supported');
      });
      return;
    }

    try {
      await resolved.initialize();
      await resolved.setLooping(true);
      if (!mounted || token != _videoRequestToken) {
        _safeDisposeVideoController(resolved);
        return;
      }
      _videoController = resolved;
      widget.onVideoControllerChanged?.call(resolved);
      _attachVideoValueListener();
      _syncVideoSnapshotFromControllerValue();
      _syncVideoPlaybackWithActivity();
    } catch (error) {
      _safeDisposeVideoController(resolved);
      if (!mounted || token != _videoRequestToken) return;
      widget.onVideoControllerChanged?.call(null);
      setState(() {
        _videoReady = false;
        _videoError = error;
      });
    }
  }

  Future<VideoPlayerController?> _resolveVideoController(String source) async {
    if (_isNetworkUrl(source)) {
      final Uri uri = Uri.tryParse(source) ?? Uri();
      if (!uri.hasScheme || uri.host.isEmpty) {
        return null;
      }
      // new
      final headers =
          PizGalleryAuthContext.resolveHeaders() ?? const <String, String>{};
      return VideoPlayerController.networkUrl(
        // Previous behavior:
        // uri
        uri,
        httpHeaders: headers,
      );
      // #new
    }

    final String? assetId = LocalDeviceMediaUri.parseOriginalAssetId(source);
    if (assetId != null) {
      final AssetEntity? asset = await AssetEntity.fromId(assetId);
      final File? file = await asset?.file;
      if (file == null) {
        return null;
      }
      return VideoPlayerController.file(file);
    }

    if (_isFilePathOrUri(source)) {
      final File? file = _fileFromPathOrUri(source);
      if (file == null) {
        return null;
      }
      return VideoPlayerController.file(file);
    }
    return null;
  }

  void _attachVideoValueListener() {
    _videoController?.addListener(_handleVideoValueChanged);
  }

  void _detachVideoValueListener() {
    _videoController?.removeListener(_handleVideoValueChanged);
  }

  void _handleVideoValueChanged() {
    if (!mounted) return;
    _syncVideoSnapshotFromControllerValue();
  }

  void _syncVideoSnapshotFromControllerValue() {
    final VideoPlayerValue? value = _videoController?.value;
    if (value == null) return;
    final bool nextReady = value.isInitialized && !value.hasError;
    final Object? nextError = value.hasError
        ? StateError(value.errorDescription ?? 'Unable to play this video')
        : null;
    final int? nextWidth = value.size.width > 0
        ? value.size.width.round()
        : null;
    final int? nextHeight = value.size.height > 0
        ? value.size.height.round()
        : null;

    if (nextReady == _videoReady &&
        nextError?.toString() == _videoError?.toString() &&
        nextWidth == _videoWidth &&
        nextHeight == _videoHeight) {
      return;
    }
    setState(() {
      _videoReady = nextReady;
      _videoError = nextError;
      _videoWidth = nextWidth;
      _videoHeight = nextHeight;
    });
  }

  void _safeDisposeVideoController(VideoPlayerController controller) {
    try {
      unawaited(controller.dispose());
    } catch (_) {
      // Ignore teardown errors while quickly switching pages.
    }
  }

  void _syncVideoPlaybackWithActivity() {
    final VideoPlayerController? controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (widget.isActive) {
      if (!controller.value.isPlaying) {
        unawaited(controller.play());
      }
    } else if (controller.value.isPlaying) {
      unawaited(controller.pause());
    }
  }

  void _disposeVideoController() {
    _videoRequestToken += 1;
    final VideoPlayerController? controller = _videoController;
    _detachVideoValueListener();
    _videoController = null;
    widget.onVideoControllerChanged?.call(null);
    _videoReady = false;
    _videoError = null;
    _videoWidth = null;
    _videoHeight = null;
    if (controller != null) {
      _safeDisposeVideoController(controller);
    }
  }

  void _handleVideoSurfaceTap() {
    widget.onSurfaceTap?.call();
  }

  Widget _buildVideoPlayer(ViewerAppearancePalette palette) {
    final Color backgroundColor = widget.useTransparentBackground
        ? Colors.transparent
        : (widget.useBlackBackground ? Colors.black : palette.mediaBackground);
    final VideoPlayerController? controller = _videoController;
    if (controller == null) {
      if (_videoError != null) {
        return ColoredBox(
          color: backgroundColor,
          child: _buildVideoUnavailable(palette),
        );
      }
      return ColoredBox(
        color: backgroundColor,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final bool hasError = _videoError != null;
    final bool isReady = _videoReady && !hasError;
    return ColoredBox(
      color: backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildVideoContent(controller),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleVideoSurfaceTap,
            ),
          ),
          if (!isReady && !hasError)
            const Positioned.fill(
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (hasError) _buildVideoUnavailable(palette),
        ],
      ),
    );
  }

  Widget _buildVideoContent(VideoPlayerController controller) {
    final Size resolvedSize = _resolveVideoSize();
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.center,
        child: SizedBox(
          width: resolvedSize.width,
          height: resolvedSize.height,
          child: IgnorePointer(ignoring: true, child: VideoPlayer(controller)),
        ),
      ),
    );
  }

  Size _resolveVideoSize() {
    if (_videoWidth != null &&
        _videoHeight != null &&
        _videoWidth! > 0 &&
        _videoHeight! > 0) {
      return Size(_videoWidth!.toDouble(), _videoHeight!.toDouble());
    }
    final double fallbackWidth =
        widget.item.width?.toDouble() ?? MediaQuery.sizeOf(context).width;
    final double aspectRatio = _resolveVideoAspectRatio();
    final double fallbackHeight =
        widget.item.height?.toDouble() ??
        (aspectRatio > 0 ? fallbackWidth / aspectRatio : fallbackWidth);
    return Size(fallbackWidth, fallbackHeight);
  }

  double _resolveVideoAspectRatio() {
    if (_videoWidth != null &&
        _videoHeight != null &&
        _videoWidth! > 0 &&
        _videoHeight! > 0) {
      return _videoWidth! / _videoHeight!;
    }
    final int? width = widget.item.width;
    final int? height = widget.item.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return 1.0;
  }

  Widget _buildVideoUnavailable(ViewerAppearancePalette palette) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.play_circle_fill_rounded,
            color: palette.videoPlaceholderIcon,
            size: 84,
          ),
          const SizedBox(height: 12),
          Text(
            'Unable to play this video',
            style: TextStyle(color: palette.videoPlaceholderText),
          ),
        ],
      ),
    );
  }
}
