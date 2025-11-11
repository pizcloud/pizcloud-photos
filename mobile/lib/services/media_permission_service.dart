import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

enum MediaPermState { full, limited, none, legacy }

enum RequestOutcome { asked, permanentlyDenied }

class MediaPermissionService {
  static const _ch = MethodChannel('app.perms');

  Future<MediaPermState> getState() async {
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
    if (!Platform.isAndroid) {
      return RequestOutcome.asked;
    }
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
