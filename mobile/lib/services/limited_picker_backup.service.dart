import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/providers/app_settings.provider.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/services/upload.service.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final limitedPickerBackupServiceProvider = Provider<LimitedPickerBackupService>((ref) {
  return LimitedPickerBackupService(ref.watch(uploadServiceProvider), ref.watch(appSettingsServiceProvider));
});

class LimitedPickerBackupService {
  LimitedPickerBackupService(this._uploadService, this._appSettingsService);

  final UploadService _uploadService;
  final AppSettingsService _appSettingsService;
  final _logger = Logger('LimitedPickerBackupService');
  final ImagePicker _picker = ImagePicker();

  Future<bool> pickAndUploadFromSystemPicker() async {
    List<XFile> medias = [];

    try {
      medias = await _picker.pickMultipleMedia();
    } catch (e, stack) {
      _logger.severe('Error opening image picker: $e', e, stack);
      return false;
    }

    if (medias.isEmpty) {
      _logger.info('User did not select any media');
      return false;
    }

    final List<UploadTask> tasks = [];

    for (final xfile in medias) {
      final file = File(xfile.path);

      if (!await file.exists()) {
        _logger.warning('Picked file does not exist: ${xfile.path}');
        continue;
      }

      final stat = await file.stat();
      final createdAt = stat.changed;
      final modifiedAt = stat.modified;

      final deviceAssetId = _buildDeviceAssetId(xfile, stat);
      final requiresWiFi = _shouldRequireWiFi(xfile);

      final task = await _uploadService.buildUploadTask(
        file,
        group: kManualUploadGroup,
        createdAt: createdAt,
        modifiedAt: modifiedAt,
        originalFileName: p.basename(xfile.path),
        deviceAssetId: deviceAssetId,
        isFavorite: false,
        requiresWiFi: requiresWiFi,
      );

      tasks.add(task);
    }

    if (tasks.isEmpty) {
      _logger.warning('No valid media files to upload after filtering');
      return false;
    }

    await _uploadService.enqueueTasks(tasks);

    _logger.info('Enqueued ${tasks.length} media files from system picker');
    return true;
  }

  String _buildDeviceAssetId(XFile file, FileStat stat) {
    final basename = p.basename(file.path);
    return 'picker_${stat.size}_${stat.modified.millisecondsSinceEpoch}_$basename';
  }

  bool _isVideo(XFile file) {
    final ext = p.extension(file.path).toLowerCase();
    return ['.mp4', '.mov', '.m4v', '.3gp', '.avi', '.mkv', '.hevc', '.webm'].contains(ext);
  }

  bool _shouldRequireWiFi(XFile file) {
    bool requiresWiFi = true;
    final isVideo = _isVideo(file);

    if (isVideo && _appSettingsService.getSetting<bool>(AppSettingsEnum.useCellularForUploadVideos)) {
      requiresWiFi = false;
    } else if (!isVideo && _appSettingsService.getSetting<bool>(AppSettingsEnum.useCellularForUploadPhotos)) {
      requiresWiFi = false;
    }

    return requiresWiFi;
  }
}
