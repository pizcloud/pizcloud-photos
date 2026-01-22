import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart'; // pizcloud

enum MediaPermState { full, limited, none, legacy }

enum RequestOutcome { asked, permanentlyDenied }

class MediaPermissionService {
  static const _ch = MethodChannel('app.perms');

  Future<MediaPermState> getState() async {
    // pizcloud
    // iOS: Read state directly from PhotoManager/permission_handler
    // so we can distinguish Full vs Limited and avoid a missing MethodChannel.
    //
    // Previous behavior (kept for reference):
    // final s = await _ch.invokeMethod<String>('mediaPermissionState');
    // switch (s) { ... }
    if (Platform.isIOS) {
      try {
        final st = await Permission.photos.status;
        if (st.isGranted) return MediaPermState.full;
        if (st.isLimited) return MediaPermState.limited;
      } catch (_) {}
      return MediaPermState.none;
    }
    // #pizcloud

    // Android: keep native channel logic for accurate 13/14+ handling.
    final s = await _ch.invokeMethod<String>('mediaPermissionState');
    switch (s) {
      case 'FULL':
        return MediaPermState.full;
      case 'LIMITED':
        return MediaPermState.limited;
      case 'LEGACY':
        return MediaPermState.legacy;
      default:
        return MediaPermState.none;
    }
  }

  Future<RequestOutcome> request() async {
    // pizcloud
    // iOS: request access and allow limited selection, then refresh in caller.
    //
    // Previous behavior (kept for reference):
    // if (!Platform.isAndroid) {
    //   return RequestOutcome.asked;
    // }
    if (Platform.isIOS) {
      try {
        await PhotoManager.requestPermissionExtend();
      } catch (_) {}
      return RequestOutcome.asked;
    }

    if (!Platform.isAndroid) return RequestOutcome.asked;
    // #pizcloud
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;

    if (sdk >= 33) {
      final results = await [
        Permission.photos, // READ_MEDIA_IMAGES
        Permission.videos, // READ_MEDIA_VIDEO
      ].request();

      final permDenied = results.values.any((s) => s.isPermanentlyDenied);
      return permDenied ? RequestOutcome.permanentlyDenied : RequestOutcome.asked;
    } else {
      final st = await Permission.storage.request(); // READ_EXTERNAL_STORAGE
      return st.isPermanentlyDenied ? RequestOutcome.permanentlyDenied : RequestOutcome.asked;
    }
  }

  Future<void> openSettings() async {
    await openAppSettings();
  }
}
