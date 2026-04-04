part of 'image_request.dart';

class RemoteImageRequest extends ImageRequest {
  static final log = Logger('RemoteImageRequest');
  static final client = HttpClient()..maxConnectionsPerHost = 16;
  final RemoteCacheManager? cacheManager;
  final String uri;
  final Map<String, String> headers;
  HttpClientRequest? _request;

  RemoteImageRequest({required this.uri, required this.headers, this.cacheManager});

  @override
  Future<ImageInfo?> load(ImageDecoderCallback decode, {double scale = 1.0}) async {
    if (_isCancelled) {
      return null;
    }

    // TODO: the cache manager makes everything sequential with its DB calls and its operations cannot be cancelled,
    //  so it ends up being a bottleneck.  We only prefer fetching from it when it can skip the DB call.
    final cachedFileImage = await _loadCachedFile(uri, decode, scale, inMemoryOnly: true);
    if (cachedFileImage != null) {
      return cachedFileImage;
    }

    try {
      final buffer = await _downloadImage(uri);
      if (buffer == null) {
        return null;
      }

      return await _decodeBuffer(buffer, decode, scale);
    } catch (e, stackTrace) {
      if (_isCancelled) {
        return null;
      }

      final cachedFileImage = await _loadCachedFile(uri, decode, scale, inMemoryOnly: false);
      if (cachedFileImage != null) {
        return cachedFileImage;
      }

      // pizcloud
      // return null;
      log.warning('Remote image request failed for $uri', e);
      Error.throwWithStackTrace(e, stackTrace);
    } finally {
      _request = null;
    }
  }

  Future<ImmutableBuffer?> _downloadImage(String url) async {
    if (_isCancelled) {
      return null;
    }

    final request = _request = await client.getUrl(Uri.parse(url));
    if (_isCancelled) {
      request.abort();
      return _request = null;
    }

    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response = await request.close();
    if (_isCancelled) {
      return null;
    }

    // pizcloud
    _validateResponse(url, response);

    final cacheManager = this.cacheManager;
    final streamController = StreamController<List<int>>(sync: true);
    final Stream<List<int>> stream;
    unawaited(cacheManager?.putStreamedFile(url, streamController.stream));
    stream = response.map((chunk) {
      if (_isCancelled) {
        throw StateError('Cancelled request');
      }
      if (cacheManager != null) {
        streamController.add(chunk);
      }
      return chunk;
    });

    try {
      final Uint8List bytes = await _downloadBytes(stream, response.contentLength);
      unawaited(streamController.close());
      return await ImmutableBuffer.fromUint8List(bytes);
    } catch (e) {
      streamController.addError(e);
      unawaited(streamController.close());
      if (_isCancelled) {
        return null;
      }
      rethrow;
    }
  }

  Future<Uint8List> _downloadBytes(Stream<List<int>> stream, int length) async {
    final Uint8List bytes;
    int offset = 0;
    if (length > 0) {
      // Known content length - use pre-allocated buffer
      bytes = Uint8List(length);
      await stream.listen((chunk) {
        bytes.setAll(offset, chunk);
        offset += chunk.length;
      }, cancelOnError: true).asFuture();
    } else {
      // Unknown content length - collect chunks dynamically
      final chunks = <List<int>>[];
      int totalLength = 0;
      await stream.listen((chunk) {
        chunks.add(chunk);
        totalLength += chunk.length;
      }, cancelOnError: true).asFuture();

      bytes = Uint8List(totalLength);
      for (final chunk in chunks) {
        bytes.setAll(offset, chunk);
        offset += chunk.length;
      }
    }

    return bytes;
  }

  Future<ImageInfo?> _loadCachedFile(
    String url,
    ImageDecoderCallback decode,
    double scale, {
    required bool inMemoryOnly,
  }) async {
    final cacheManager = this.cacheManager;
    if (_isCancelled || cacheManager == null) {
      return null;
    }

    final file = await (inMemoryOnly ? cacheManager.getFileFromMemory(url) : cacheManager.getFileFromCache(url));
    if (_isCancelled || file == null) {
      return null;
    }

    try {
      // pizcloud
      final bytes = await file.file.readAsBytes();
      if (_isCancelled) {
        return null;
      }

      // Skip decoding obvious non-image payloads (e.g. cached JSON/HTML error bodies)
      // to avoid platform decoder errors and evict them immediately.
      if (_isClearlyNotImageBytes(bytes)) {
        log.warning('Cached payload is not an image, evicting: $url');
        unawaited(_evictFile(url));
        return null;
      }

      final buffer = await ImmutableBuffer.fromUint8List(bytes);
      // #pizcloud
      return await _decodeBuffer(buffer, decode, scale);
    } catch (e) {
      log.warning('Failed to decode cached image', e); // pizcloud
      unawaited(_evictFile(url));
      return null;
    }
  }

  Future<void> _evictFile(String url) async {
    try {
      await cacheManager?.removeFile(url);
    } catch (e) {
      log.severe('Failed to remove cached image', e);
    }
  }

  Future<ImageInfo?> _decodeBuffer(ImmutableBuffer buffer, ImageDecoderCallback decode, scale) async {
    if (_isCancelled) {
      buffer.dispose();
      return null;
    }
    final codec = await decode(buffer);
    if (_isCancelled) {
      buffer.dispose();
      codec.dispose();
      return null;
    }
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image, scale: scale);
  }

  @override
  void _onCancelled() {
    _request?.abort();
    _request = null;
  }

  // pizcloud
  void _validateResponse(String url, HttpClientResponse response) {
    final statusCode = response.statusCode;
    if (statusCode < HttpStatus.ok || statusCode >= HttpStatus.multipleChoices) {
      throw HttpException('Unexpected status code $statusCode for $url');
    }

    final mimeType = response.headers.contentType?.mimeType.toLowerCase();
    // If the server sets a specific content type and it is clearly not an image,
    // fail early to avoid caching/decoding invalid payloads.
    if (mimeType != null && mimeType.isNotEmpty && !_isLikelyImageMimeType(mimeType)) {
      throw HttpException('Unexpected content type "$mimeType" for $url');
    }
  }

  bool _isLikelyImageMimeType(String mimeType) {
    if (mimeType.startsWith('image/')) {
      return true;
    }

    // Some proxies/backends may serve image bytes with a generic mime type.
    return mimeType == 'application/octet-stream';
  }

  bool _isClearlyNotImageBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      return true;
    }

    if (_hasKnownImageSignature(bytes)) {
      return false;
    }

    // Common non-image response starts
    int i = 0;
    while (i < bytes.length && _isWhitespace(bytes[i])) {
      i++;
    }
    if (i >= bytes.length) {
      return true;
    }

    final first = bytes[i];
    // '{' JSON object, '[' JSON array, '<' HTML/XML
    return first == 0x7B || first == 0x5B || first == 0x3C;
  }

  bool _isWhitespace(int byte) => byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D;

  bool _hasKnownImageSignature(Uint8List bytes) {
    // JPEG: FF D8 FF
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return true;
    }

    // GIF: "GIF8"
    if (_hasAsciiAt(bytes, 0, 'GIF8')) {
      return true;
    }

    // WEBP: "RIFF....WEBP"
    if (_hasAsciiAt(bytes, 0, 'RIFF') && _hasAsciiAt(bytes, 8, 'WEBP')) {
      return true;
    }

    // BMP: "BM"
    if (_hasAsciiAt(bytes, 0, 'BM')) {
      return true;
    }

    // TIFF: II*<NUL> / MM<NUL>*
    if (bytes.length >= 4 &&
        ((bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00) ||
            (bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A))) {
      return true;
    }

    // HEIF/AVIF container marker
    if (_hasAsciiAt(bytes, 4, 'ftyp')) {
      return true;
    }

    return false;
  }

  bool _hasAsciiAt(Uint8List bytes, int offset, String value) {
    if (offset < 0 || bytes.length < offset + value.length) {
      return false;
    }

    for (int i = 0; i < value.length; i++) {
      if (bytes[offset + i] != value.codeUnitAt(i)) {
        return false;
      }
    }
    return true;
  }

  // #pizcloud
}
