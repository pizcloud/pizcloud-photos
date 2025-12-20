import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/services/pizcloud/photos_base_url.service.dart';
import 'package:immich_mobile/utils/debug_print.dart';

class PhotosApiUrlRefresher {
  PhotosApiUrlRefresher(
    this._ref, {
    PhotosBaseUrlService? baseUrlService,
    Duration interval = const Duration(minutes: 1),
  }) : _baseUrlService = baseUrlService ?? PhotosBaseUrlService(),
       _interval = interval;

  final Ref _ref;
  final PhotosBaseUrlService _baseUrlService;
  final Duration _interval;

  Timer? _timer;
  bool _isRefreshing = false;

  Future<void> start() async {
    if (_timer != null) return;

    await _refreshOnce();
    _timer = Timer.periodic(_interval, (_) {
      unawaited(_refreshOnce());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _refreshOnce() async {
    if (_isRefreshing) return;
    if (!_ref.read(authProvider).isAuthenticated) return;

    _isRefreshing = true;
    try {
      await _baseUrlService.fetchApiUrlFromRef(_ref);
    } catch (e) {
      dPrint(() => 'PhotosApiUrlRefresher refresh failed: $e');
    } finally {
      _isRefreshing = false;
    }
  }
}
