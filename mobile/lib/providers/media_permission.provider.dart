import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/media_permission_service.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:immich_mobile/providers/backup/backup.provider.dart';

final mediaPermissionServiceProvider = Provider<MediaPermissionService>((ref) {
  return MediaPermissionService();
});

class MediaPermissionController extends StateNotifier<MediaPermState> {
  MediaPermissionController(this._svc, this._ref) : super(MediaPermState.none) {
    refresh();
  }
  final MediaPermissionService _svc;
  final Ref _ref;

  Future<void> refresh() async {
    state = await _svc.getState();
  }

  Future<void> _waitAppResumed({Duration timeout = const Duration(minutes: 2)}) async {
    final c = Completer<void>();
    late final WidgetsBindingObserver obs;
    obs = _OneShotObserver(
      onResumed: () {
        if (!c.isCompleted) c.complete();
        WidgetsBinding.instance.removeObserver(obs);
      },
    );
    WidgetsBinding.instance.addObserver(obs);
    unawaited(
      Future.delayed(timeout, () {
        if (!c.isCompleted) {
          c.complete();
          WidgetsBinding.instance.removeObserver(obs);
        }
      }),
    );
    await c.future;
  }

  Future<bool> openSettingsAndRefreshOnReturn() async {
    await _svc.openSettings();
    await _waitAppResumed();
    await refresh();
    return state == MediaPermState.full || state == MediaPermState.legacy;
  }

  Future<(bool ok, bool permanentlyDenied)> requestAndRefresh({bool preferFullOnAndroid = true}) async {
    if (preferFullOnAndroid && Platform.isAndroid && state == MediaPermState.limited) {
      final okNow = await openSettingsAndRefreshOnReturn();
      return (okNow, false);
    }

    final outcome = await _svc.request();
    await refresh();
    final ok = (state == MediaPermState.full || state == MediaPermState.legacy);
    return (ok, outcome == RequestOutcome.permanentlyDenied);
  }

  Future<(bool ok, bool permanentlyDenied)> requestAndRefreshNormal() async {
    final outcome = await _svc.request();
    await refresh();
    final ok = (state == MediaPermState.full || state == MediaPermState.legacy);
    return (ok, outcome == RequestOutcome.permanentlyDenied);
  }

  Future<void> openSettings() => _svc.openSettings();

  Future<bool> presentLimitedPhotosPickerAndRefresh() async {
    if (state != MediaPermState.limited) {
      await refresh();
      return state == MediaPermState.full || state == MediaPermState.legacy || state == MediaPermState.limited;
    }

    final wasLimited = state;

    try {
      if (Platform.isIOS) {
        await PhotoManager.presentLimited(type: RequestType.common);
      } else if (Platform.isAndroid) {
        await PhotoManager.requestPermissionExtend();
      }
    } catch (_) {}

    await refresh();

    unawaited(_ref.read(backupProvider.notifier).getBackupInfo());

    if (Platform.isAndroid && wasLimited == MediaPermState.limited && state == MediaPermState.limited) {
      await openSettingsAndRefreshOnReturn();
      unawaited(_ref.read(backupProvider.notifier).getBackupInfo());
    }

    return state == MediaPermState.full || state == MediaPermState.legacy || state == MediaPermState.limited;
  }
}

class _OneShotObserver with WidgetsBindingObserver {
  _OneShotObserver({required this.onResumed});
  final VoidCallback onResumed;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}

final mediaPermissionProvider = StateNotifierProvider<MediaPermissionController, MediaPermState>((ref) {
  return MediaPermissionController(ref.read(mediaPermissionServiceProvider), ref);
});
