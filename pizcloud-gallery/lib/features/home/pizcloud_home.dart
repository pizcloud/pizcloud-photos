import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../media/pizcloud_media.dart';
import '../../ui/tabs/simple_tab.dart';
import '../../ui/widgets/platform_widgets.dart';
import '../activity/activity_tab.dart';
import '../library/library_tab.dart';
import '../test/test_tab.dart';

class PizCloudHomePage extends StatefulWidget {
  const PizCloudHomePage({super.key});

  @override
  State<PizCloudHomePage> createState() => _PizCloudHomePageState();
}

class _PizCloudHomePageState extends State<PizCloudHomePage> {
  late final MediaRepository _mediaRepository;
  late final LocalMediaScanner _mediaScanner;
  late Future<ActivitySummary> _activityFuture;
  DateTime? _lastScanAt;
  int _currentIndex = 0;
  int _libraryReselectSignal = 0;

  @override
  void initState() {
    super.initState();
    /*_mediaRepository = MediaRepository();
    _mediaScanner = LocalMediaScanner(repository: _mediaRepository);
    _activityFuture = Future.value(
      ActivitySummary(
        scan: const LocalScanResult(
          scanned: 0,
          upserted: 0,
          permissionGranted: true,
        ),
        localOnly: 0,
        cloudOnly: 0,
        synced: 0,
        scannedAt: DateTime.now(),
        hasScan: false,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshActivity();
    });*/
  }

  Future<ActivitySummary> _loadActivity() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      return ActivitySummary(
        scan: const LocalScanResult(
          scanned: 0,
          upserted: 0,
          permissionGranted: false,
        ),
        localOnly: 0,
        cloudOnly: 0,
        synced: 0,
        scannedAt: DateTime.now(),
        hasScan: true,
      );
    }

    final scan = await _mediaScanner.scanAndUpsert(checkPermission: false);
    _lastScanAt = DateTime.now();
    final localOnly = await _mediaRepository.countBySyncState(
      SyncState.localOnly,
    );
    final cloudOnly = await _mediaRepository.countBySyncState(
      SyncState.cloudOnly,
    );
    final synced = await _mediaRepository.countBySyncState(SyncState.synced);
    return ActivitySummary(
      scan: scan,
      localOnly: localOnly,
      cloudOnly: cloudOnly,
      synced: synced,
      scannedAt: _lastScanAt!,
      hasScan: true,
    );
  }

  Future<void> _refreshActivity() async {
    setState(() {
      _activityFuture = _loadActivity();
    });
    await _activityFuture;
  }

  final PlatformTabController _tabController = PlatformTabController();

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged(int index) {
    if (index == _currentIndex) {
      if (index == 0) {
        setState(() {
          _libraryReselectSignal++;
        });
      }
      return;
    }
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PlatformTabScaffold(
      tabController: _tabController,
      itemChanged: _handleTabChanged,
      items: [
        BottomNavigationBarItem(
          icon: const PizPlatformIcon(
            materialIcon: Icons.photo_library,
            cupertinoIcon: CupertinoIcons.photo_on_rectangle,
          ),
          activeIcon: const PizPlatformIcon(
            materialIcon: Icons.photo_library_outlined,
            cupertinoIcon: CupertinoIcons.photo_on_rectangle,
          ),
          label: 'Library',
        ),
        BottomNavigationBarItem(
          icon: const PizPlatformIcon(
            materialIcon: Icons.cloud_upload,
            cupertinoIcon: CupertinoIcons.cloud,
          ),
          activeIcon: const PizPlatformIcon(
            materialIcon: Icons.cloud_upload_outlined,
            cupertinoIcon: CupertinoIcons.cloud,
          ),
          label: 'Backup',
        ),
        BottomNavigationBarItem(
          icon: const PizPlatformIcon(
            materialIcon: Icons.notifications,
            cupertinoIcon: CupertinoIcons.bell,
          ),
          activeIcon: const PizPlatformIcon(
            materialIcon: Icons.notifications_outlined,
            cupertinoIcon: CupertinoIcons.bell,
          ),
          label: 'Activity',
        ),
        BottomNavigationBarItem(
          icon: const PizPlatformIcon(
            materialIcon: Icons.grid_on,
            cupertinoIcon: CupertinoIcons.rectangle_grid_2x2,
          ),
          activeIcon: const PizPlatformIcon(
            materialIcon: Icons.grid_on_outlined,
            cupertinoIcon: CupertinoIcons.rectangle_grid_2x2,
          ),
          label: 'Test',
        ),
        BottomNavigationBarItem(
          icon: const PizPlatformIcon(
            materialIcon: Icons.settings,
            cupertinoIcon: CupertinoIcons.settings,
          ),
          activeIcon: const PizPlatformIcon(
            materialIcon: Icons.settings_outlined,
            cupertinoIcon: CupertinoIcons.settings,
          ),
          label: 'Settings',
        ),
      ],
      appBarBuilder: (context, index) {
        switch (index) {
          case 0:
            return PlatformAppBar(title: const Text('PizCloud Photos'));
          case 1:
            return PlatformAppBar(title: const Text('Backup'));
          case 2:
            return PlatformAppBar(title: const Text('Activity'));
          case 3:
            return PlatformAppBar(title: const Text('Test'));
          case 4:
            return PlatformAppBar(title: const Text('Settings'));
          default:
            return PlatformAppBar(title: const Text('PizCloud Photos'));
        }
      },
      bodyBuilder: (context, index) {
        final tabKey = ValueKey('tab-$index');
        switch (index) {
          case 0:
            return KeyedSubtree(
              key: tabKey,
              child: LibraryTabBody(reselectSignal: _libraryReselectSignal),
            );
          case 1:
            return KeyedSubtree(
              key: tabKey,
              child: const SimpleTabBody(title: 'Backup'),
            );
          case 2:
            return ActivityTabBody(
              future: _activityFuture,
              onRefresh: _refreshActivity,
            );
          case 3:
            return KeyedSubtree(key: tabKey, child: const TestTabBody());
          case 4:
            return KeyedSubtree(
              key: tabKey,
              child: const SimpleTabBody(title: 'Settings'),
            );
          default:
            return KeyedSubtree(
              key: tabKey,
              child: LibraryTabBody(reselectSignal: _libraryReselectSignal),
            );
        }
      },
    );
  }
}
