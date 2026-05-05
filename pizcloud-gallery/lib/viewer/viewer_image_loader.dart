import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pizcloud_gallery/auth/piz_gallery_auth_context.dart'; // new
import 'package:pizcloud_gallery/grid/media_item.dart';
import 'package:pizcloud_gallery/grid/sources/local_device_media_uri.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import 'viewer_appearance_config.dart';
import 'viewer_cache_manager.dart';
import 'viewer_local_preview_cache.dart';

part 'viewer_image_loader_video.dart';

class ViewerImageLoader extends StatefulWidget {
  const ViewerImageLoader({
    super.key,
    required this.item,
    required this.viewerIndex,
    required this.isActive,
    this.onSurfaceTap,
    this.startWithHighQuality = false,
    this.initialThumbUrl, // new
    this.initialThumbBytes, // new
    this.useTransparentBackground = false,
    this.useBlackBackground = false,
    this.videoControlsBottomInset = 12,
    this.videoControlsEnabled = true,
    this.onVideoControllerChanged,
  });

  final MediaItem item;
  final int viewerIndex;
  final bool isActive;
  final VoidCallback? onSurfaceTap;
  final bool startWithHighQuality;
  final String? initialThumbUrl; // new
  final Uint8List? initialThumbBytes; // new
  final bool useTransparentBackground;
  final bool useBlackBackground;
  final double videoControlsBottomInset;
  final bool videoControlsEnabled;
  final ValueChanged<VideoPlayerController?>? onVideoControllerChanged;

  @override
  State<ViewerImageLoader> createState() => _ViewerImageLoaderState();
}

class _ViewerImageLoaderState extends State<ViewerImageLoader> {
  bool _originalCached = false;
  bool _previewCached = false;
  bool _thumb300Cached = false; // new
  bool _thumb100Cached = false; // new
  String? _cachedLowQualityUrl; // new
  int _cacheStatusToken = 0;
  bool _allowHighQualityRequest = false;

  bool _lowQualityReady = false;
  Object? _lowQualityError;
  String? _requestedLowQualityUrl;
  ImageStream? _lowQualityStream;
  ImageStreamListener? _lowQualityListener;

  bool _highQualityReady = false;
  Object? _highQualityError;
  String? _requestedHighQualityUrl;
  int? _requestedHighQualityWidth;
  ImageStream? _highQualityStream;
  ImageStreamListener? _highQualityListener;
  String? _localAssetFutureId;
  Future<File?>? _localAssetFileFuture;
  VideoPlayerController? _videoController;
  int _videoRequestToken = 0;
  bool _videoReady = false;
  Object? _videoError;
  int? _videoWidth;
  int? _videoHeight;
  String? _localPreviewFutureSource;
  Future<Uint8List?>? _localPreviewBytesFuture;

  @override
  void initState() {
    super.initState();
    if (widget.item.isVideo) {
      _prepareVideoController();
    }
    if (widget.startWithHighQuality) {
      _markOriginalReady();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.startWithHighQuality || widget.item.isVideo) {
      return;
    }
    _startLoadPipeline();
  }

  @override
  void didUpdateWidget(covariant ViewerImageLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _disposeVideoController();
      if (widget.item.isVideo) {
        _prepareVideoController();
      }
    } else if (!oldWidget.item.isVideo && widget.item.isVideo) {
      _prepareVideoController();
    } else if (oldWidget.item.isVideo && !widget.item.isVideo) {
      _disposeVideoController();
    } else if (widget.item.isVideo &&
        oldWidget.item.originalUrl != widget.item.originalUrl) {
      _prepareVideoController();
    }
    if (widget.item.isVideo &&
        oldWidget.isActive != widget.isActive &&
        _videoReady) {
      // new
      // _syncVideoPlaybackWithActivity();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.item.isVideo || !_videoReady) {
          return;
        }
        _syncVideoPlaybackWithActivity();
      });
      // #new
    }
    if (oldWidget.item.id != widget.item.id) {
      _localAssetFutureId = null;
      _localAssetFileFuture = null;
      _localPreviewFutureSource = null;
      _localPreviewBytesFuture = null;
      _detachLowQualityListener();
      _detachHighQualityListener();
      _resetState();
      if (widget.startWithHighQuality) {
        _markOriginalReady();
      }
      if (widget.startWithHighQuality) {
        return;
      }
      _startLoadPipeline();
    }
  }

  @override
  void dispose() {
    _detachLowQualityListener();
    _detachHighQualityListener();
    _disposeVideoController();
    super.dispose();
  }

  void _ensureLowQualityRequested() {
    if (widget.item.isVideo) {
      return;
    } // new
    final String? lowQualityUrl = _resolveLowQualityUrl();
    if (!_isNetworkUrl(lowQualityUrl)) {
      _onLowQualityGateOpened();
      return;
    }
    if (_requestedLowQualityUrl == lowQualityUrl) {
      if (_lowQualityReady || _lowQualityError != null) {
        _allowHighQualityRequest = true;
        _onLowQualityGateOpened();
      }
      return;
    }
    final String resolvedLowQualityUrl = lowQualityUrl!;

    _detachLowQualityListener();
    _requestedLowQualityUrl = resolvedLowQualityUrl;
    _lowQualityReady = false;
    _lowQualityError = null;

    final ImageProvider<Object> provider = ViewerCacheManager.providerFor(
      resolvedLowQualityUrl,
      debugIndex: widget.viewerIndex,
    );
    final ImageStream stream = provider.resolve(
      createLocalImageConfiguration(context),
    );
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (imageInfo, synchronousCall) {
        _detachLowQualityListener();
        if (!mounted) return;
        setState(() {
          _lowQualityReady = true;
          _lowQualityError = null;
        });
        _onLowQualityGateOpened();
      },
      onError: (Object error, StackTrace? stackTrace) {
        _detachLowQualityListener();
        if (!mounted) return;
        setState(() {
          _lowQualityError = error;
        });
        _onLowQualityGateOpened();
      },
    );
    _lowQualityStream = stream;
    _lowQualityListener = listener;
    stream.addListener(listener);
  }

  void _ensureHighQualityRequested() {
    if (widget.item.isVideo) {
      return;
    } // new
    final String highQualityUrl = widget.item.originalUrl;
    if (!_isNetworkUrl(highQualityUrl)) return;
    if (_originalCached) return;
    if (!_allowHighQualityRequest) return;
    final int decodeWidth = _decodeWidth();
    final int? decodeHeight = _decodeHeightForWidth(decodeWidth);
    if (_requestedHighQualityUrl == highQualityUrl &&
        _requestedHighQualityWidth == decodeWidth) {
      return;
    }

    _detachHighQualityListener();
    _requestedHighQualityUrl = highQualityUrl;
    _requestedHighQualityWidth = decodeWidth;
    _highQualityReady = false;
    _highQualityError = null;

    final ImageProvider<Object> provider = ViewerCacheManager.providerFor(
      highQualityUrl,
      maxWidth: decodeWidth,
      maxHeight: decodeHeight,
      debugIndex: widget.viewerIndex,
    );
    final ImageStream stream = provider.resolve(
      createLocalImageConfiguration(context),
    );
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (imageInfo, synchronousCall) {
        _detachHighQualityListener();
        if (!mounted) return;
        setState(() {
          _highQualityReady = true;
          _highQualityError = null;
        });
      },
      onError: (Object error, StackTrace? stackTrace) {
        _detachHighQualityListener();
        if (!mounted) return;
        setState(() {
          _highQualityError = error;
        });
      },
    );
    _highQualityStream = stream;
    _highQualityListener = listener;
    stream.addListener(listener);
  }

  Future<void> _refreshCacheStatus() async {
    final String highQualityUrl = widget.item.originalUrl;
    // new
    // final String? previewUrl = _normalizedPreviewUrl();
    final String? previewUrl = _normalizedPreviewUrl(
      highQualityUrl: highQualityUrl,
    );
    final String? thumb300Url = _normalizedThumbnailUrl(
      widget.item.thumbnails.size300,
      highQualityUrl: highQualityUrl,
    );
    final String? thumb100Url = _normalizedThumbnailUrl(
      widget.item.thumbnails.size100,
      highQualityUrl: highQualityUrl,
    );
    // #new
    final int token = ++_cacheStatusToken;
    final int decodeWidth = _decodeWidth();
    final int? decodeHeight = _decodeHeightForWidth(decodeWidth);

    final Future<bool> originalCachedFuture = _isNetworkUrl(highQualityUrl)
        ? _isCached(
            provider: ViewerCacheManager.providerFor(
              highQualityUrl,
              maxWidth: decodeWidth,
              maxHeight: decodeHeight,
              debugIndex: widget.viewerIndex,
            ),
            url: highQualityUrl,
            maxWidth: decodeWidth,
            maxHeight: decodeHeight,
          )
        : Future<bool>.value(false);
    final Future<bool> previewCachedFuture =
        _isNetworkUrl(previewUrl) && previewUrl != highQualityUrl
        ? _isCached(
            provider: ViewerCacheManager.providerFor(
              previewUrl!,
              debugIndex: widget.viewerIndex,
            ),
            url: previewUrl,
          )
        : Future<bool>.value(false);
    // new
    final Future<bool> thumb300CachedFuture =
        _isNetworkUrl(thumb300Url) && thumb300Url != highQualityUrl
        ? _isCached(
            provider: ViewerCacheManager.providerFor(
              thumb300Url!,
              debugIndex: widget.viewerIndex,
            ),
            url: thumb300Url,
          )
        : Future<bool>.value(false);
    final Future<bool> thumb100CachedFuture =
        _isNetworkUrl(thumb100Url) && thumb100Url != highQualityUrl
        ? _isCached(
            provider: ViewerCacheManager.providerFor(
              thumb100Url!,
              debugIndex: widget.viewerIndex,
            ),
            url: thumb100Url,
          )
        : Future<bool>.value(false);
    // #new

    final List<bool> cacheResults = await Future.wait<bool>([
      originalCachedFuture,
      previewCachedFuture,
      thumb300CachedFuture, // new
      thumb100CachedFuture, // new
    ]);
    if (!mounted || token != _cacheStatusToken) return;

    final bool nextCached = cacheResults[0];
    final bool nextPreviewCached = cacheResults[1];
    // new
    final bool nextThumb300Cached = cacheResults[2];
    final bool nextThumb100Cached = cacheResults[3];
    String? nextCachedLowQualityUrl;
    // Prioritize smaller cached thumbs for faster first-frame display.
    if (nextThumb300Cached && _isNetworkUrl(thumb300Url)) {
      nextCachedLowQualityUrl = thumb300Url;
    } else if (nextThumb100Cached && _isNetworkUrl(thumb100Url)) {
      nextCachedLowQualityUrl = thumb100Url;
    } else if (nextPreviewCached && _isNetworkUrl(previewUrl)) {
      nextCachedLowQualityUrl = previewUrl;
    }
    // #new

    final bool nextHighQualityReady = _highQualityReady || nextCached;
    if (nextCached == _originalCached &&
        nextPreviewCached == _previewCached &&
        nextThumb300Cached == _thumb300Cached &&
        nextThumb100Cached == _thumb100Cached &&
        nextCachedLowQualityUrl == _cachedLowQualityUrl && // new
        nextHighQualityReady == _highQualityReady) {
      return;
    }
    if (nextCached) {
      _detachHighQualityListener();
      _detachLowQualityListener();
    }
    setState(() {
      _originalCached = nextCached;
      _previewCached = nextPreviewCached;
      _thumb300Cached = nextThumb300Cached; // new
      _thumb100Cached = nextThumb100Cached; // new
      _cachedLowQualityUrl = nextCached ? null : nextCachedLowQualityUrl; // new
      _highQualityReady = nextHighQualityReady;
      if (_originalCached) {
        _lowQualityReady = false;
        _lowQualityError = null;
        _requestedHighQualityUrl = null;
        _requestedHighQualityWidth = null;
      }
    });
  }

  void _detachHighQualityListener() {
    final ImageStream? stream = _highQualityStream;
    final ImageStreamListener? listener = _highQualityListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _highQualityStream = null;
    _highQualityListener = null;
  }

  void _detachLowQualityListener() {
    final ImageStream? stream = _lowQualityStream;
    final ImageStreamListener? listener = _lowQualityListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _lowQualityStream = null;
    _lowQualityListener = null;
  }

  void _resetState() {
    _originalCached = false;
    _previewCached = false;
    _thumb300Cached = false; // new
    _thumb100Cached = false; // new
    _cachedLowQualityUrl = null; // new
    _lowQualityReady = false;
    _lowQualityError = null;
    _requestedLowQualityUrl = null;
    _highQualityReady = false;
    _highQualityError = null;
    _requestedHighQualityUrl = null;
    _requestedHighQualityWidth = null;
    _allowHighQualityRequest = false;
  }

  void _markOriginalReady() {
    _originalCached = true;
    _previewCached = false;
    _thumb300Cached = false; // new
    _thumb100Cached = false; // new
    _cachedLowQualityUrl = null; // new
    _highQualityReady = true;
    _highQualityError = null;
    _lowQualityReady = false;
    _lowQualityError = null;
    _requestedLowQualityUrl = null;
    _requestedHighQualityUrl = widget.item.originalUrl;
    // Avoid MediaQuery access during initState; width is resolved lazily in build.
    _requestedHighQualityWidth = null;
    _allowHighQualityRequest = false;
  }

  @override
  Widget build(BuildContext context) {
    final ViewerAppearancePalette palette = ViewerAppearancePalette.of(context);
    if (widget.item.isVideo) {
      return _buildVideoPlayer(palette);
    }

    final String highQualityUrl = widget.item.originalUrl;
    final String? localAssetId = LocalDeviceMediaUri.parseOriginalAssetId(
      highQualityUrl,
    );
    if (localAssetId != null) {
      return _buildLocalAssetImage(localAssetId, palette);
    }
    if (_isFilePathOrUri(highQualityUrl)) {
      return _buildLocalFileImage(highQualityUrl, palette);
    }
    if (!_isNetworkUrl(highQualityUrl)) {
      return _buildErrorPlaceholder(palette);
    }

    final String? lowQualityUrl = _resolveLowQualityUrl();
    return ColoredBox(
      color: widget.useTransparentBackground
          ? Colors.transparent
          : (widget.useBlackBackground
                ? Colors.black
                : palette.mediaBackground),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildForegroundContent(
            highQualityUrl: highQualityUrl,
            lowQualityUrl: lowQualityUrl,
          ),
          if (_shouldShowLoadingOverlay(highQualityUrl, lowQualityUrl))
            Positioned.fill(child: Center(child: _buildLoadingOverlay())),
        ],
      ),
    );
  }

  bool _shouldShowLoadingOverlay(String highQualityUrl, String? lowQualityUrl) {
    if (_hasImmediateInitialHandoffFrame()) {
      // new
      return false;
    }
    final bool loadingPreview =
        _isNetworkUrl(lowQualityUrl) &&
        _requestedLowQualityUrl == lowQualityUrl &&
        !_lowQualityReady &&
        _lowQualityError == null;
    final bool loadingOriginal =
        _allowHighQualityRequest &&
        _requestedHighQualityUrl == highQualityUrl &&
        !_highQualityReady &&
        _highQualityError == null;
    return loadingPreview || loadingOriginal;
  }

  Widget _buildLoadingOverlay() {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Widget _buildForegroundContent({
    required String highQualityUrl,
    required String? lowQualityUrl,
  }) {
    final ViewerAppearancePalette palette = ViewerAppearancePalette.of(context);
    final Widget? handoff = _buildInitialHandoffImageOrNull(); // new
    if (_highQualityReady) {
      return _buildHighQualityImage(highQualityUrl);
    }
    // new
    if (_isNetworkUrl(lowQualityUrl) &&
        _lowQualityReady &&
        _shouldKeepInitialHandoffBeforeHighQuality(lowQualityUrl!)) {
      if (handoff != null) {
        return handoff;
      }
    }
    // #new
    if (_isNetworkUrl(lowQualityUrl) && _lowQualityReady) {
      return _buildLowQualityImage(lowQualityUrl!);
    }
    if (_lowQualityError != null && _highQualityError != null) {
      return _buildErrorPlaceholder(palette);
    }
    if (_highQualityError != null) {
      return _buildErrorPlaceholder(palette);
    }
    if (handoff != null) {
      return handoff;
    } // new
    return const SizedBox(key: ValueKey<String>('loading'));
  }

  // new
  bool _shouldKeepInitialHandoffBeforeHighQuality(String lowQualityUrl) {
    if (_highQualityReady || _highQualityError != null) {
      return false;
    }
    final Uint8List? bytes = widget.initialThumbBytes;
    if (bytes == null || bytes.isEmpty) {
      return false;
    }
    final String initialSource = widget.initialThumbUrl?.trim() ?? '';
    if (initialSource.isEmpty) {
      return false;
    }
    return initialSource == lowQualityUrl;
  }

  bool _shouldUseInitialHandoffFrame() {
    if (_highQualityReady || _lowQualityReady) {
      return false;
    }
    if (_lowQualityError != null || _highQualityError != null) {
      return false;
    }
    if (_hasImmediateInitialHandoffFrame()) {
      return true;
    }
    return false;
  }

  bool _hasImmediateInitialHandoffFrame() {
    final Uint8List? bytes = widget.initialThumbBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return true;
    }
    final String source = widget.initialThumbUrl?.trim() ?? '';
    if (source.isEmpty) {
      return false;
    }
    if (_isFilePathOrUri(source)) {
      return _fileFromPathOrUri(source) != null;
    }
    return false;
  }

  Widget? _buildInitialHandoffImageOrNull() {
    if (!_shouldUseInitialHandoffFrame()) {
      return null;
    }
    final Uint8List? bytes = widget.initialThumbBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        key: const ValueKey<String>('viewer_image_content'),
        fit: BoxFit.fitWidth,
        alignment: Alignment.center,
        width: double.infinity,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
      );
    }
    final String source = widget.initialThumbUrl!.trim();

    final File? file = _fileFromPathOrUri(source);
    if (file == null) {
      return null;
    }
    return Image.file(
      file,
      key: const ValueKey<String>('viewer_image_content'),
      fit: BoxFit.fitWidth,
      alignment: Alignment.center,
      width: double.infinity,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return const SizedBox.shrink();
      },
    );
  }
  // #new

  Widget _buildLowQualityImage(String url) {
    return Image(
      key: const ValueKey<String>('viewer_image_content'), // new
      // key: const ValueKey<String>('low_quality'), // new
      image: ViewerCacheManager.providerFor(
        url,
        debugIndex: widget.viewerIndex,
      ),
      fit: BoxFit.fitWidth,
      alignment: Alignment.center,
      width: double.infinity,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return const SizedBox.shrink();
      },
    );
  }

  Future<bool> _isCached({
    required ImageProvider<Object> provider,
    required String url,
    int? maxWidth,
    int? maxHeight,
  }) async {
    final bool inDisk = await ViewerCacheManager.instance.isCachedOnDisk(
      url,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
    if (inDisk) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    final ImageConfiguration config = createLocalImageConfiguration(context);
    final ImageCacheStatus? status = await provider.obtainCacheStatus(
      configuration: config,
    );
    return status?.tracked ?? false;
  }

  Widget _buildHighQualityImage(String url) {
    final int decodeWidth = _requestedHighQualityWidth ?? _decodeWidth();
    final int? decodeHeight = _decodeHeightForWidth(decodeWidth);
    return Image(
      key: const ValueKey<String>('viewer_image_content'), // new
      // key: const ValueKey<String>('high_quality'),
      image: ViewerCacheManager.providerFor(
        url,
        maxWidth: decodeWidth,
        maxHeight: decodeHeight,
        debugIndex: widget.viewerIndex,
      ),
      fit: BoxFit.fitWidth,
      alignment: Alignment.center,
      width: double.infinity,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        final ViewerAppearancePalette palette = ViewerAppearancePalette.of(
          context,
        );
        return _buildErrorPlaceholder(palette);
      },
    );
  }

  String? _resolveLowQualityUrl() {
    if (_originalCached) {
      return null;
    }

    // new
    // Prefer cached small thumbs first (300/100), then cached preview.
    final String? cachedCandidate = _cachedLowQualityUrl;
    if (_isNetworkUrl(cachedCandidate)) {
      return cachedCandidate;
    }

    // final String? fromPreview = _normalizedPreviewUrl();
    // if (_previewCached && _isNetworkUrl(fromPreview)) {
    //   return fromPreview;
    // }
    // if (_isNetworkUrl(fromPreview)) {
    //   return fromPreview;
    // }
    // final String fallback = widget.item.thumbnails.size600;
    // if (_isNetworkUrl(fallback) && fallback != widget.item.originalUrl) {
    //   return fallback;
    // }

    final String highQualityUrl = widget.item.originalUrl;
    final String? fromPreview = _normalizedPreviewUrl(
      highQualityUrl: highQualityUrl,
    );
    // #new
    if (_isNetworkUrl(fromPreview)) {
      return fromPreview;
    }

    final String? fromThumb300 = _normalizedThumbnailUrl(
      widget.item.thumbnails.size300,
      highQualityUrl: highQualityUrl,
    ); // new
    if (_isNetworkUrl(fromThumb300)) {
      return fromThumb300;
    } // new

    // new
    final String? fromThumb100 = _normalizedThumbnailUrl(
      widget.item.thumbnails.size100,
      highQualityUrl: highQualityUrl,
    );
    if (_isNetworkUrl(fromThumb100)) {
      return fromThumb100;
    }

    final String? fallback = _normalizedThumbnailUrl(
      widget.item.thumbnails.size600,
      highQualityUrl: highQualityUrl,
    );
    if (_isNetworkUrl(fallback)) {
      return fallback;
    }
    // #new
    return null;
  }

  bool _isNetworkUrl(String? value) {
    if (value == null || value.isEmpty) return false;
    return value.startsWith('http://') || value.startsWith('https://');
  }

  bool _isFilePathOrUri(String? value) {
    if (value == null || value.isEmpty) return false;
    if (value.startsWith('/')) return true;
    return value.startsWith('file://');
  }

  File? _fileFromPathOrUri(String value) {
    if (value.isEmpty) return null;
    if (value.startsWith('file://')) {
      final Uri uri = Uri.tryParse(value) ?? Uri();
      if (uri.scheme != 'file' || uri.path.isEmpty) {
        return null;
      }
      return File.fromUri(uri);
    }
    return File(value);
  }

  String? _normalizedPreviewUrl({String? highQualityUrl}) {
    // new
    final String? value = widget.item.previewUrl;
    final String comparedHighQualityUrl =
        highQualityUrl ?? widget.item.originalUrl; // new
    if (!_isNetworkUrl(value)) {
      return null;
    }
    if (value == comparedHighQualityUrl) {
      return null;
    } // new
    return value;
  }

  // new
  String? _normalizedThumbnailUrl(String? value, {String? highQualityUrl}) {
    final String comparedHighQualityUrl =
        highQualityUrl ?? widget.item.originalUrl;
    if (!_isNetworkUrl(value)) {
      return null;
    }
    if (value == comparedHighQualityUrl) {
      return null;
    }
    return value;
  }
  // #new

  void _startLoadPipeline() {
    if (widget.item.isVideo) {
      return;
    } // new
    // Reverted behavior (requested):
    // - Keep low-quality gate first to avoid competing with high-quality fetch
    //   on weak/limited networks.
    // - High-quality request is unlocked in `_onLowQualityGateOpened`.
    _allowHighQualityRequest = false;
    // "HQ sooner" version kept for reference:
    // _allowHighQualityRequest = true;
    // _ensureLowQualityRequested();
    // _ensureHighQualityRequested();
    _refreshCacheStatus().then((_) {
      if (!mounted) return;
      if (_originalCached) {
        return;
      }
      _ensureLowQualityRequested();
      _ensureHighQualityRequested();
    });
  }

  void _onLowQualityGateOpened() {
    _allowHighQualityRequest = true;
    _refreshCacheStatus().then((_) {
      if (!mounted) return;
      if (_originalCached) return;
      _ensureHighQualityRequested();
    });
  }

  int _decodeWidth() {
    final int decodeWidth = ViewerCacheManager.decodeWidthForContext(context);
    final int? originalWidth = widget.item.width;
    if (originalWidth == null || originalWidth <= 0) {
      return decodeWidth;
    }
    return decodeWidth.clamp(1, originalWidth).toInt();
  }

  int? _decodeHeightForWidth(int decodeWidth) {
    final int? originalWidth = widget.item.width;
    final int? originalHeight = widget.item.height;
    if (originalWidth == null ||
        originalHeight == null ||
        originalWidth <= 0 ||
        originalHeight <= 0 ||
        decodeWidth <= 0) {
      return null;
    }
    final int scaledHeight = (decodeWidth * originalHeight / originalWidth)
        .round()
        .clamp(1, originalHeight)
        .toInt();
    return scaledHeight;
  }

  Widget _buildErrorPlaceholder(ViewerAppearancePalette palette) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: palette.errorPlaceholderIcon,
            size: 54,
          ),
          const SizedBox(height: 8),
          Text(
            'Unable to load image',
            style: TextStyle(color: palette.errorPlaceholderText),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalFileImage(String source, ViewerAppearancePalette palette) {
    final File? file = _fileFromPathOrUri(source);
    if (file == null) {
      return _buildErrorPlaceholder(palette);
    }
    return Image.file(
      file,
      key: ValueKey<String>('local_file_high_quality_${file.path}'),
      fit: BoxFit.fitWidth,
      alignment: Alignment.center,
      width: double.infinity,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return _buildErrorPlaceholder(palette);
      },
    );
  }

  Widget _buildLocalAssetImage(
    String assetId,
    ViewerAppearancePalette palette,
  ) {
    final Future<File?> future = _localAssetFileFutureFor(assetId);
    return FutureBuilder<File?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildLocalPreviewOrLoading(palette);
        }
        final File? file = snapshot.data;
        if (file == null) {
          final Widget? preview = _buildLocalPreviewOrNull();
          return preview ?? _buildErrorPlaceholder(palette);
        }
        final Widget previewUnderlay = _buildLocalPreviewUnderlay();
        return Stack(
          fit: StackFit.expand,
          children: [
            previewUnderlay,
            Image.file(
              file,
              key: ValueKey<String>('local_asset_high_quality_${file.path}'),
              fit: BoxFit.fitWidth,
              alignment: Alignment.center,
              width: double.infinity,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) {
                  return child;
                }
                // Keep preview visible until full-res frame is ready.
                return const SizedBox.shrink();
              },
              errorBuilder: (context, error, stackTrace) {
                return _buildErrorPlaceholder(palette);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildLocalPreviewOrLoading(ViewerAppearancePalette palette) {
    final Widget? preview = _buildLocalPreviewOrNull();
    if (preview != null) {
      return preview;
    }
    return const Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget? _buildLocalPreviewOrNull() {
    final String? source = _resolveLocalPreviewSource();
    if (source == null) {
      return null;
    }
    final Uint8List? cachedBytes = ViewerLocalPreviewCache.peek(source);
    if (cachedBytes != null && cachedBytes.isNotEmpty) {
      return _buildLocalPreviewImage(cachedBytes);
    }
    final Future<Uint8List?> future = _localPreviewBytesFutureFor(source);
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        final Uint8List? bytes = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (bytes == null || bytes.isEmpty) {
          return const SizedBox.shrink();
        }
        ViewerLocalPreviewCache.put(source, bytes);
        return _buildLocalPreviewImage(bytes);
      },
    );
  }

  Widget _buildLocalPreviewUnderlay() {
    final String? source = _resolveLocalPreviewSource();
    if (source == null) {
      return const SizedBox.shrink();
    }
    final Uint8List? cachedBytes = ViewerLocalPreviewCache.peek(source);
    if (cachedBytes != null && cachedBytes.isNotEmpty) {
      return _buildLocalPreviewImage(cachedBytes);
    }
    final Future<Uint8List?> future = _localPreviewBytesFutureFor(source);
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        final Uint8List? bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return const SizedBox.shrink();
        }
        ViewerLocalPreviewCache.put(source, bytes);
        return _buildLocalPreviewImage(bytes);
      },
    );
  }

  Widget _buildLocalPreviewImage(Uint8List bytes) {
    return Image.memory(
      bytes,
      fit: BoxFit.fitWidth,
      alignment: Alignment.center,
      width: double.infinity,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
    );
  }

  String? _resolveLocalPreviewSource() {
    return ViewerLocalPreviewCache.pickPreviewSource(widget.item);
  }

  Future<Uint8List?> _localPreviewBytesFutureFor(String source) {
    if (_localPreviewFutureSource == source &&
        _localPreviewBytesFuture != null) {
      return _localPreviewBytesFuture!;
    }
    _localPreviewFutureSource = source;
    _localPreviewBytesFuture = ViewerLocalPreviewCache.resolve(source);
    return _localPreviewBytesFuture!;
  }

  Future<File?> _localAssetFileFutureFor(String assetId) {
    if (_localAssetFutureId == assetId && _localAssetFileFuture != null) {
      return _localAssetFileFuture!;
    }
    _localAssetFutureId = assetId;
    _localAssetFileFuture = _resolveAssetFile(assetId);
    return _localAssetFileFuture!;
  }

  Future<File?> _resolveAssetFile(String assetId) async {
    final AssetEntity? asset = await AssetEntity.fromId(assetId);
    if (asset == null) {
      return null;
    }
    return asset.file;
  }
}
