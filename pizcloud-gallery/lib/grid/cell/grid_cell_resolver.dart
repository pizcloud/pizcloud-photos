part of '../grid_cell.dart';

extension _GridCellStateResolver on _GridCellState {
  void _syncProvider({bool force = false}) {
    final MediaItem? media = widget.data.mediaItem;
    if (media == null) {
      _cancelPendingLocalResolve();
      _cancelPendingResolve();
      if (_shownProvider != null || _shownRequest != null) {
        _setState(() {
          _shownProvider = null;
          _shownRequest = null;
        });
      }
      return;
    }

    if (media.isLocal) {
      _syncLocalProvider(media, force: force);
      return;
    }
    _cancelPendingLocalResolve();

    final _ThumbRequest request = _buildRequest(media);
    if (request.thumbUrl.isEmpty) {
      _cancelPendingResolve();
      _commitNoProvider(request);
      return;
    }

    if (widget.bytesCache.contains(request.thumbUrl)) {
      final Uint8List? cachedBytes = widget.bytesCache.get(request.thumbUrl);
      if (cachedBytes != null &&
          (_shownRequest != request || _shownProvider == null)) {
        _setState(() {
          _shownRequest = request;
          _shownProvider = MemoryImage(cachedBytes);
        });
      }
      _cancelPendingResolve();
      return;
    }

    if (!force && _shownRequest != null && _shownRequest == request) {
      return;
    }
    if (!force && _pendingRequest != null && _pendingRequest == request) {
      return;
    }

    final ImageProvider<Object> nextProvider =
        GridThumbnailCacheManager.buildImageProvider(
          request.thumbUrl,
          decodeWidth: request.decodeSide,
          decodeHeight: null,
        );

    if (_shownProvider == null || _shownRequest == null) {
      final _ShownThumb? remembered =
          _GridCellState._shownByMediaId[request.mediaId];
      if (remembered != null) {
        _setState(() {
          _shownRequest = remembered.request;
          _shownProvider = remembered.provider;
        });
        if (remembered.request == request) {
          return;
        }
        _resolveAndSwap(request: request, provider: nextProvider);
        return;
      }

      // First paint fallback: no previous frame for this media yet.
      _setState(() {
        _shownRequest = request;
        _shownProvider = nextProvider;
      });
      _rememberShown(request: request, provider: nextProvider);
      return;
    }

    _resolveAndSwap(request: request, provider: nextProvider);
  }

  void _cancelPendingLocalResolve() {
    _localResolveToken += 1;
    _cancelEmergencyVisibleThumbEnqueue();
  }

  _ThumbRequest _buildRequest(MediaItem media) {
    final int thumbEdge =
        widget.data.thumbEdge ??
        media.thumbnails.adaptiveEdge(
          cellSize: widget.size,
          scale: widget.data.renderScale,
          currentColCount: widget.data.currentColCount,
          targetColCount: widget.data.targetColCount,
          preferTargetColCount: widget.data.preferTargetColCount,
        );
    final String overrideUrl = widget.data.thumbUrl?.trim() ?? '';
    final String resolvedThumbUrl = overrideUrl.isNotEmpty
        ? overrideUrl
        : (media.pickGridThumbForEdge(thumbEdge) ?? '');
    final double dpr = MediaQuery.of(context).devicePixelRatio;
    final int decodeSide = math.max(
      1,
      math.min(
        thumbEdge,
        (widget.size * widget.data.renderScale * dpr).round(),
      ),
    );
    return _ThumbRequest(
      mediaId: media.id,
      thumbUrl: resolvedThumbUrl,
      decodeSide: decodeSide,
    );
  }

  void _syncLocalProvider(MediaItem media, {required bool force}) {
    _cancelPendingResolve();
    final _LocalSourceRequest request = _buildLocalSourceRequest(media);
    if (media.isVideo) {
      _syncLocalVideoProvider(request, force: force);
      return;
    }
    _syncLocalImageProvider(request, force: force);
  }

  void _syncLocalImageProvider(
    _LocalSourceRequest request, {
    required bool force,
  }) {
    if (!force &&
        _shownRequest != null &&
        _shownRequest == request.thumb &&
        _shownProvider != null) {
      return;
    }
    if (!force && _pendingRequest != null && _pendingRequest == request.thumb) {
      return;
    }

    final Uint8List? cachedBytes = widget.bytesCache.peek(request.cacheKey);
    _reportLocalCacheLookup(
      hit: cachedBytes != null && cachedBytes.isNotEmpty,
      fromRenderStage: false,
      noKey: request.cacheKey.isEmpty,
      key: request.cacheKey,
    );
    if (cachedBytes != null) {
      _cancelEmergencyVisibleThumbEnqueue();
      _cancelPendingLocalResolve();
      _rememberLocalCellFrame(key: request.cacheKey, bytes: cachedBytes);
      _setShownProvider(
        request: request.thumb,
        provider: MemoryImage(cachedBytes),
      );
      return;
    }

    if (_shownProvider == null || _shownRequest == null) {
      final _ShownThumb? remembered =
          _GridCellState._shownByMediaId[request.thumb.mediaId];
      if (remembered != null) {
        _setState(() {
          _shownRequest = remembered.request;
          _shownProvider = remembered.provider;
        });
        if (remembered.request == request.thumb) {
          return;
        }
      }
    }

    switch (request.kind) {
      case _LocalSourceKind.assetThumb:
        _scheduleEmergencyVisibleThumbEnqueue(
          sourceKey: request.cacheKey,
          assetId: request.assetId,
          edge: request.edge,
          isVideo: false,
        );
        _commitNoProvider(request.thumb);
        return;
      case _LocalSourceKind.assetFile:
        _startResolveLocalAssetFile(
          request: request.thumb,
          sourceKey: request.cacheKey,
          assetId: request.assetId,
        );
        return;
      case _LocalSourceKind.filePath:
        _cancelPendingLocalResolve();
        _resolveAndSwap(
          request: request.thumb,
          provider: FileImage(request.file!),
        );
        return;
      case _LocalSourceKind.unsupported:
        _cancelPendingLocalResolve();
        _commitNoProvider(request.thumb);
        return;
    }
  }

  void _syncLocalVideoProvider(
    _LocalSourceRequest request, {
    required bool force,
  }) {
    if (!force &&
        _shownRequest != null &&
        _shownRequest == request.thumb &&
        (_shownProvider != null || _isFailedLocalThumbKey(request.cacheKey))) {
      return;
    }
    if (!force && _pendingRequest != null && _pendingRequest == request.thumb) {
      return;
    }

    final Uint8List? cachedBytes = widget.bytesCache.peek(request.cacheKey);
    _reportLocalCacheLookup(
      hit: cachedBytes != null && cachedBytes.isNotEmpty,
      fromRenderStage: false,
      noKey: request.cacheKey.isEmpty,
      key: request.cacheKey,
    );
    if (cachedBytes != null) {
      _cancelEmergencyVisibleThumbEnqueue();
      _cancelPendingLocalResolve();
      _rememberLocalCellFrame(key: request.cacheKey, bytes: cachedBytes);
      _setShownProvider(
        request: request.thumb,
        provider: MemoryImage(cachedBytes),
      );
      return;
    }

    if (_shownProvider == null || _shownRequest == null) {
      final _ShownThumb? remembered =
          _GridCellState._shownByMediaId[request.thumb.mediaId];
      if (remembered != null) {
        _setState(() {
          _shownRequest = remembered.request;
          _shownProvider = remembered.provider;
        });
        if (remembered.request == request.thumb) {
          return;
        }
      }
    }

    switch (request.kind) {
      case _LocalSourceKind.assetThumb:
        _scheduleEmergencyVisibleThumbEnqueue(
          sourceKey: request.cacheKey,
          assetId: request.assetId,
          edge: request.edge,
          isVideo: true,
        );
        _commitNoProvider(request.thumb);
        return;
      case _LocalSourceKind.assetFile:
      case _LocalSourceKind.filePath:
      case _LocalSourceKind.unsupported:
        _cancelPendingLocalResolve();
        _markFailedLocalThumbKey(request.cacheKey);
        _commitNoProvider(request.thumb);
        return;
    }
  }

  _LocalSourceRequest _buildLocalSourceRequest(MediaItem media) {
    final String source =
        (widget.data.thumbUrl ??
                media.previewUrl ??
                media.localPath ??
                media.originalUrl)
            .trim();
    final String cacheKey = source.isEmpty
        ? ''
        : LocalDeviceMediaUri.buildTypedThumbCacheKey(
            source,
            isVideo: media.isVideo,
          );
    if (source.isEmpty) {
      return _LocalSourceRequest.unsupported(
        source: '',
        cacheKey: '',
        thumb: _ThumbRequest(mediaId: media.id, thumbUrl: '', decodeSide: 0),
      );
    }
    final ({String assetId, int edge})? thumbUri =
        LocalDeviceMediaUri.parseThumbUri(source);
    if (thumbUri != null) {
      return _LocalSourceRequest.assetThumb(
        source: source,
        cacheKey: cacheKey,
        thumb: _ThumbRequest(
          mediaId: media.id,
          thumbUrl: source,
          decodeSide: thumbUri.edge,
        ),
        assetId: thumbUri.assetId,
        edge: thumbUri.edge,
      );
    }
    final String? originalAssetId = LocalDeviceMediaUri.parseOriginalAssetId(
      source,
    );
    if (originalAssetId != null) {
      return _LocalSourceRequest.assetFile(
        source: source,
        cacheKey: cacheKey,
        thumb: _ThumbRequest(
          mediaId: media.id,
          thumbUrl: source,
          decodeSide: 0,
        ),
        assetId: originalAssetId,
      );
    }
    final File? file = _fileFromPathOrUri(source);
    if (file != null) {
      return _LocalSourceRequest.filePath(
        source: source,
        cacheKey: cacheKey,
        thumb: _ThumbRequest(
          mediaId: media.id,
          thumbUrl: source,
          decodeSide: 0,
        ),
        file: file,
      );
    }
    return _LocalSourceRequest.unsupported(
      source: source,
      cacheKey: cacheKey,
      thumb: _ThumbRequest(mediaId: media.id, thumbUrl: source, decodeSide: 0),
    );
  }

  void _scheduleEmergencyVisibleThumbEnqueue({
    required String sourceKey,
    required String assetId,
    required int edge,
    required bool isVideo,
  }) {
    if (sourceKey.isEmpty || assetId.isEmpty) {
      return;
    }
    if (_localEmergencyEnqueueKey == sourceKey &&
        _localEmergencyEnqueueTimer?.isActive == true) {
      return;
    }
    _cancelEmergencyVisibleThumbEnqueue();
    _localEmergencyEnqueueKey = sourceKey;
    _localEmergencyEnqueueTimer = Timer(
      _GridCellState._localEmergencyEnqueueDelay,
      () {
        _localEmergencyEnqueueTimer = null;
        final String? key = _localEmergencyEnqueueKey;
        _localEmergencyEnqueueKey = null;
        if (!mounted || key == null || key.isEmpty) {
          return;
        }
        final Uint8List? existing = widget.bytesCache.peek(key);
        if (existing != null && existing.isNotEmpty) {
          return;
        }
        LocalThumbRequestQueue.instance.enqueue(
          LocalThumbRequest(
            cacheKey: key,
            dataIndex: widget.data.dataIndex ?? -1,
            assetId: assetId,
            edge: edge,
            isVideo: isVideo,
            priority: -1,
            isInViewport: true,
            source: LocalThumbRequestSource.visible,
          ),
        );
      },
    );
  }

  void _cancelEmergencyVisibleThumbEnqueue() {
    _localEmergencyEnqueueTimer?.cancel();
    _localEmergencyEnqueueTimer = null;
    _localEmergencyEnqueueKey = null;
  }

  void _startResolveLocalAssetFile({
    required _ThumbRequest request,
    required String sourceKey,
    required String assetId,
  }) {
    final int token = ++_localResolveToken;
    unawaited(
      _localAssetFileFutureFor(assetId: assetId)
          .then((File? file) {
            if (!mounted || token != _localResolveToken) {
              return;
            }
            if (file == null) {
              _markFailedLocalThumbKey(sourceKey);
              _commitNoProvider(request);
              return;
            }
            _resolveAndSwap(request: request, provider: FileImage(file));
          })
          .catchError((Object _) {
            if (!mounted || token != _localResolveToken) {
              return;
            }
            _markFailedLocalThumbKey(sourceKey);
            _commitNoProvider(request);
          }),
    );
  }

  void _setShownProvider({
    required _ThumbRequest request,
    required ImageProvider<Object> provider,
  }) {
    if (_shownRequest == request && _shownProvider != null) {
      return;
    }
    _setState(() {
      _shownRequest = request;
      _shownProvider = provider;
    });
    _rememberShown(request: request, provider: provider);
  }

  void _commitNoProvider(_ThumbRequest request) {
    if (_shownRequest == request && _shownProvider == null) {
      return;
    }
    _setState(() {
      _shownRequest = request;
      _shownProvider = null;
    });
    _GridCellState._shownByMediaId.remove(request.mediaId);
  }

  void _resolveAndSwap({
    required _ThumbRequest request,
    required ImageProvider<Object> provider,
  }) {
    _cancelPendingResolve();
    final int token = ++_requestToken;
    final ImageStream stream = provider.resolve(
      createLocalImageConfiguration(context),
    );
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (imageInfo, synchronousCall) {
        if (!mounted || token != _requestToken) return;
        _cancelPendingResolve();
        _setState(() {
          _shownRequest = request;
          _shownProvider = provider;
        });
        _rememberShown(request: request, provider: provider);
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!mounted || token != _requestToken) return;
        _cancelPendingResolve();
        // Commit the new request even on error so the cell does not keep
        // showing stale media after it has been reassigned.
        _setState(() {
          _shownRequest = request;
          _shownProvider = provider;
        });
      },
    );
    _pendingRequest = request;
    _pendingStream = stream;
    _pendingListener = listener;
    stream.addListener(listener);
  }

  void _cancelPendingResolve() {
    final ImageStream? stream = _pendingStream;
    final ImageStreamListener? listener = _pendingListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _pendingRequest = null;
    _pendingStream = null;
    _pendingListener = null;
  }

  void _rememberShown({
    required _ThumbRequest request,
    required ImageProvider<Object> provider,
  }) {
    _GridCellState._shownByMediaId.remove(request.mediaId);
    _GridCellState._shownByMediaId[request.mediaId] = _ShownThumb(
      request: request,
      provider: provider,
    );
    while (_GridCellState._shownByMediaId.length >
        _GridCellState._maxRememberedProviders) {
      _GridCellState._shownByMediaId.remove(
        _GridCellState._shownByMediaId.keys.first,
      );
    }
  }

  bool _isFilePathOrUri(String value) {
    if (value.isEmpty) return false;
    if (value.startsWith('/')) return true;
    return value.startsWith('file://');
  }

  File? _fileFromPathOrUri(String value) {
    if (!_isFilePathOrUri(value)) return null;
    if (value.startsWith('file://')) {
      final Uri uri = Uri.tryParse(value) ?? Uri();
      if (uri.scheme != 'file' || uri.path.isEmpty) {
        return null;
      }
      return File.fromUri(uri);
    }
    return File(value);
  }

  Future<File?> _localAssetFileFutureFor({required String assetId}) {
    final Future<File?>? existing = _GridCellState._localAssetFileFutureById
        .remove(assetId);
    if (existing != null) {
      _GridCellState._localAssetFileFutureById[assetId] = existing;
      return existing;
    }
    final Future<File?> created = _resolveLocalAssetFile(assetId: assetId);
    _GridCellState._localAssetFileFutureById[assetId] = created;
    while (_GridCellState._localAssetFileFutureById.length >
        _GridCellState._maxRememberedLocalAssetFileFutures) {
      _GridCellState._localAssetFileFutureById.remove(
        _GridCellState._localAssetFileFutureById.keys.first,
      );
    }
    return created;
  }

  bool _isFailedLocalThumbKey(String key) {
    if (key.isEmpty) {
      return false;
    }
    final bool? known = _GridCellState._failedLocalThumbByKey.remove(key);
    if (known == null) {
      return false;
    }
    _GridCellState._failedLocalThumbByKey[key] = known;
    return known;
  }

  void _markFailedLocalThumbKey(String key) {
    if (key.isEmpty) {
      return;
    }
    _GridCellState._failedLocalThumbByKey.remove(key);
    _GridCellState._failedLocalThumbByKey[key] = true;
    while (_GridCellState._failedLocalThumbByKey.length >
        _GridCellState._maxRememberedLocalThumbFailures) {
      _GridCellState._failedLocalThumbByKey.remove(
        _GridCellState._failedLocalThumbByKey.keys.first,
      );
    }
  }
}

Future<File?> _resolveLocalAssetFile({required String assetId}) async {
  try {
    final AssetEntity? asset = await AssetEntity.fromId(assetId);
    if (asset == null || asset.type != AssetType.image) {
      return null;
    }
    return asset.file;
  } catch (_) {
    return null;
  }
}
