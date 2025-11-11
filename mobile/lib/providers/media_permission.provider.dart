import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/media_permission_service.dart';

final mediaPermissionServiceProvider = Provider<MediaPermissionService>((ref) {
  return MediaPermissionService();
});

class MediaPermissionController extends StateNotifier<MediaPermState> {
  MediaPermissionController(this._svc) : super(MediaPermState.none) {
    refresh();
  }
  final MediaPermissionService _svc;

  Future<void> refresh() async {
    state = await _svc.getState();
  }

  /// Returns true if FULL/LEGACY permission is granted after requesting.
  /// If permanentlyDenied -> returns false so the UI can show a guide dialog.
  Future<(bool ok, bool permanentlyDenied)> requestAndRefresh() async {
    final outcome = await _svc.request();
    await refresh();
    final ok = (state == MediaPermState.full || state == MediaPermState.legacy);
    return (ok, outcome == RequestOutcome.permanentlyDenied);
  }

  Future<void> openSettings() => _svc.openSettings();
}

final mediaPermissionProvider = StateNotifierProvider<MediaPermissionController, MediaPermState>((ref) {
  return MediaPermissionController(ref.read(mediaPermissionServiceProvider));
});
