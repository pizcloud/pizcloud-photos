import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// ============================
/// LRU memory cache (bytes) + notifier
/// - `size=100` local thumbs use a dedicated RAM bucket.
/// - all other thumbs share the default RAM bucket.
/// ============================
class LruBytesCache {
  LruBytesCache({required this.maxBytes, this.size50MaxBytes})
    : assert(maxBytes > 0);

  final int maxBytes;
  final int? size50MaxBytes;

  // tick de cell rebuild khi cache update
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  final LinkedHashMap<String, Uint8List> _defaultMap = LinkedHashMap();
  final LinkedHashMap<String, Uint8List> _size50Map = LinkedHashMap();
  final Map<String, ValueNotifier<int>> _keySignals =
      <String, ValueNotifier<int>>{};
  int _defaultBytes = 0;
  int _size50Bytes = 0;

  int get length => _defaultMap.length + _size50Map.length;
  int get totalBytes => _defaultBytes + _size50Bytes;
  int get defaultBytes => _defaultBytes;
  int get size50Bytes => _size50Bytes;

  bool contains(String key) {
    if (_isSize50ThumbKey(key)) {
      return _size50Map.containsKey(key);
    }
    return _defaultMap.containsKey(key);
  }

  ValueNotifier<int> listenableOf(String key) {
    return _keySignals.putIfAbsent(key, () => ValueNotifier<int>(0));
  }

  Uint8List? peek(String key) {
    if (_isSize50ThumbKey(key)) {
      return _size50Map[key];
    }
    return _defaultMap[key];
  }

  Uint8List? get(String key) {
    final bool isSize50 = _isSize50ThumbKey(key);
    final LinkedHashMap<String, Uint8List> map = isSize50
        ? _size50Map
        : _defaultMap;
    final Uint8List? bytes = map.remove(key);
    if (bytes == null) {
      return null;
    }
    map[key] = bytes; // move to most-recent
    return bytes;
  }

  void put(String key, Uint8List bytes) {
    // Ensure a key is not present in both buckets.
    _removeFromDefault(key);
    _removeFromSize50(key);

    final bool isSize50 = _isSize50ThumbKey(key);
    if (isSize50) {
      _size50Map[key] = bytes;
      _size50Bytes += bytes.lengthInBytes;
    } else {
      _defaultMap[key] = bytes;
      _defaultBytes += bytes.lengthInBytes;
    }
    _bumpSignal(key);

    final int size50Budget = size50MaxBytes == null || size50MaxBytes! <= 0
        ? maxBytes
        : size50MaxBytes!;
    _evictIfNeeded(
      map: _size50Map,
      isSize50: true,
      maxAllowedBytes: size50Budget,
    );
    _evictIfNeeded(
      map: _defaultMap,
      isSize50: false,
      maxAllowedBytes: maxBytes,
    );
    tick.value++;
  }

  void _evictIfNeeded({
    required LinkedHashMap<String, Uint8List> map,
    required bool isSize50,
    required int maxAllowedBytes,
  }) {
    while (_bucketBytes(isSize50) > maxAllowedBytes && map.isNotEmpty) {
      final String removedKey = map.keys.first;
      final Uint8List? removedBytes = map.remove(removedKey);
      if (removedBytes != null) {
        _subtractBucketBytes(isSize50, removedBytes.lengthInBytes);
      }
      _bumpSignal(removedKey);
    }
  }

  int _bucketBytes(bool isSize50) {
    return isSize50 ? _size50Bytes : _defaultBytes;
  }

  void _subtractBucketBytes(bool isSize50, int bytes) {
    if (bytes <= 0) {
      return;
    }
    if (isSize50) {
      _size50Bytes -= bytes;
      if (_size50Bytes < 0) {
        _size50Bytes = 0;
      }
      return;
    }
    _defaultBytes -= bytes;
    if (_defaultBytes < 0) {
      _defaultBytes = 0;
    }
  }

  void _removeFromDefault(String key) {
    final Uint8List? previous = _defaultMap.remove(key);
    if (previous != null) {
      _defaultBytes -= previous.lengthInBytes;
      if (_defaultBytes < 0) {
        _defaultBytes = 0;
      }
    }
  }

  void _removeFromSize50(String key) {
    final Uint8List? previous = _size50Map.remove(key);
    if (previous != null) {
      _size50Bytes -= previous.lengthInBytes;
      if (_size50Bytes < 0) {
        _size50Bytes = 0;
      }
    }
  }

  void _bumpSignal(String key) {
    final ValueNotifier<int> signal = _keySignals.putIfAbsent(
      key,
      () => ValueNotifier<int>(0),
    );
    signal.value++;
  }

  bool _isSize50ThumbKey(String key) {
    final int separatorIndex = key.indexOf('::');
    final String source = separatorIndex >= 0
        ? key.substring(separatorIndex + 2)
        : key;
    final Uri? uri = Uri.tryParse(source);
    if (uri == null || uri.scheme != 'pm-thumb') {
      return false;
    }
    final String raw =
        uri.queryParameters['s'] ?? uri.queryParameters['size'] ?? '';
    final int? edge = int.tryParse(raw);
    return edge == 100;
  }
}
