import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart'
    hide isCupertino;
import '../../media/pizcloud_media.dart';
import '../../ui/utils/formatters.dart';
import '../../ui/utils/platform_utils.dart';
import '../../ui/widgets/platform_widgets.dart';

class ActivitySummary {
  const ActivitySummary({
    required this.scan,
    required this.localOnly,
    required this.cloudOnly,
    required this.synced,
    required this.scannedAt,
    required this.hasScan,
  });

  final LocalScanResult scan;
  final int localOnly;
  final int cloudOnly;
  final int synced;
  final DateTime scannedAt;
  final bool hasScan;
}

class ActivityTabBody extends StatelessWidget {
  const ActivityTabBody({
    super.key,
    required this.future,
    required this.onRefresh,
  });

  final Future<ActivitySummary> future;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<ActivitySummary>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Scan failed: ${snapshot.error}'),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(
              child: Text('No activity data'),
            );
          }

          if (!data.hasScan) {
            return Center(
              child: Text(
                'Preparing to scan the library.\nPlease wait a moment.',
                textAlign: TextAlign.center,
              ),
            );
          }

          if (!data.scan.permissionGranted) {
            return Center(
              child: Text(
                'Photo/video library permission not granted.\n'
                'Please allow access to scan your library.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Last scan',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  PlatformTextButton(
                    onPressed: onRefresh,
                    child: const Text('Rescan'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ActivityInfoCard(
                title: 'Scan summary',
                rows: [
                  _ActivityInfoRow(
                    label: 'Scanned',
                    value: '${data.scan.scanned} items',
                    iconMaterial: Icons.search,
                    iconCupertino: CupertinoIcons.search,
                  ),
                  _ActivityInfoRow(
                    label: 'Updated',
                    value: '${data.scan.upserted} items',
                    iconMaterial: Icons.save,
                    iconCupertino: CupertinoIcons.checkmark_seal,
                  ),
                  _ActivityInfoRow(
                    label: 'Time',
                    value: formatDateTime(data.scannedAt),
                    iconMaterial: Icons.schedule,
                    iconCupertino: CupertinoIcons.time,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ActivityInfoCard(
                title: 'Sync status',
                rows: [
                  _ActivityInfoRow(
                    label: 'Not synced',
                    value: '${data.localOnly}',
                    iconMaterial: Icons.cloud_off,
                    iconCupertino: CupertinoIcons.cloud,
                  ),
                  _ActivityInfoRow(
                    label: 'Cloud only',
                    value: '${data.cloudOnly}',
                    iconMaterial: Icons.cloud_download,
                    iconCupertino: CupertinoIcons.cloud_download,
                  ),
                  _ActivityInfoRow(
                    label: 'Synced',
                    value: '${data.synced}',
                    iconMaterial: Icons.cloud_done,
                    iconCupertino: CupertinoIcons.cloud_fill,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ActivityInfoCard extends StatelessWidget {
  const _ActivityInfoCard({
    required this.title,
    required this.rows,
  });

  final String title;
  final List<_ActivityInfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final isCupertinoTarget = isCupertino(context);
    final cardColor = isCupertinoTarget
        ? CupertinoColors.systemGroupedBackground.resolveFrom(context)
        : Theme.of(context).colorScheme.surface;
    final borderColor = isCupertinoTarget
        ? CupertinoColors.separator.resolveFrom(context)
        : Theme.of(context).colorScheme.outlineVariant;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            Row(
              children: [
                PizPlatformIcon(
                  materialIcon: row.iconMaterial,
                  cupertinoIcon: row.iconCupertino,
                  color: Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    row.label,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Text(
                  row.value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            if (row != rows.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ActivityInfoRow {
  const _ActivityInfoRow({
    required this.label,
    required this.value,
    required this.iconMaterial,
    required this.iconCupertino,
  });

  final String label;
  final String value;
  final IconData iconMaterial;
  final IconData iconCupertino;
}
