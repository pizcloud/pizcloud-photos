import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pizcloud_gallery/grid/piz_gallery.dart';
import 'package:pizcloud_gallery/grid/sources/json_asset_gallery_source.dart';

class LibraryTabBody extends StatefulWidget {
  const LibraryTabBody({super.key, this.reselectSignal = 0});

  final int reselectSignal;

  @override
  State<LibraryTabBody> createState() => _LibraryTabBodyState();
}

class _LibraryTabBodyState extends State<LibraryTabBody> {
  late final LocalDatabaseGallerySource _localSource =
      LocalDatabaseGallerySource(initialLoadCount: 120);
  late final PizGallerySource _remoteSource = JsonAssetGallerySource(
    assetPath: 'assets/mock/picsum_media_sample.json',
    limit: 1000,
  );
  late final PizGallerySource _source = HybridGallerySource(
    local: _localSource,
    remote: _remoteSource,
    priority: HybridMergePriority.localFirst,
    deduplicateById: true,
  );
  late final LocalGalleryScanProcess _scanProcess = LocalGalleryScanProcess(
    source: _localSource,
    periodicInterval: const Duration(minutes: 15),
    startImmediately: true,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_scanProcess.start());
  }

  @override
  void dispose() {
    unawaited(_scanProcess.dispose());
    super.dispose();
  }

  Future<void> _handleViewerDeleteRequested(MediaItem item) async {
    debugPrint(
      'Viewer delete requested: id=${item.id}, '
      'type=${item.type.name}, source=${item.sourceType.name}, '
      'url=${item.originalUrl}',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Delete requested: ${item.id}')));
  }

  Future<void> _handleViewerShareRequested(MediaItem item) async {
    debugPrint(
      'Viewer share requested: id=${item.id}, '
      'type=${item.type.name}, source=${item.sourceType.name}, '
      'url=${item.originalUrl}',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Share requested: ${item.id}')));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return SizedBox(
          width: width,
          height: height,
          child: PizGallery(
            source: _source,
            scrollToTopSignal: widget.reselectSignal,
            onViewerShareRequested: _handleViewerShareRequested,
            onViewerDeleteRequested: _handleViewerDeleteRequested,
          ),
        );
      },
    );
  }
}
