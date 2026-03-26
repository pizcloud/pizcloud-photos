// ignore_for_file: require_trailing_commas

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'; // pizcloud
import 'package:immich_mobile/domain/models/memory.model.dart';
import 'package:immich_mobile/presentation/pages/pizcloud/new_library_view_in_timeline_helper.dart'; // pizcloud

class DriftMemoryBottomInfo extends ConsumerWidget {
  // pizcloud
  final DriftMemory memory;
  final String title;
  const DriftMemoryBottomInfo({super.key, required this.memory, required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat.yMMMMd();
    final fileCreatedDate = memory.assets.first.createdAt;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: Colors.grey[400], fontSize: 13.0, fontWeight: FontWeight.w500),
              ),
              Text(
                df.format(fileCreatedDate),
                style: const TextStyle(color: Colors.white, fontSize: 15.0, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          Tooltip(
            message: 'view_in_timeline'.tr(),
            child: MaterialButton(
              minWidth: 0,
              onPressed: () async {
                await focusNewLibraryAndLocateAsset(context: context, ref: ref, asset: memory.assets.first); // pizcloud
              },
              shape: const CircleBorder(),
              color: Colors.white.withValues(alpha: 0.2),
              elevation: 0,
              child: const Icon(Icons.open_in_new, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
