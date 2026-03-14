import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pizcloud_gallery/grid/media_item.dart';

import 'viewer_appearance_config.dart';
import 'viewer_controller.dart';

class ViewerActionContext {
  const ViewerActionContext({required this.context, required this.controller});

  final BuildContext context;
  final ViewerController controller;
}

abstract class ViewerAction {
  const ViewerAction();

  String get id;
  String get label;
  IconData get icon;

  bool isVisible(MediaItem item) => true;
  Future<void> execute(ViewerActionContext context, MediaItem item);
}

class CopyImageUrlAction extends ViewerAction {
  const CopyImageUrlAction();

  @override
  String get id => 'copy_image_url';

  @override
  String get label => 'Copy image URL';

  @override
  IconData get icon => Icons.link_rounded;

  @override
  bool isVisible(MediaItem item) {
    final String value = item.originalUrl;
    return value.startsWith('http://') || value.startsWith('https://');
  }

  @override
  Future<void> execute(ViewerActionContext context, MediaItem item) async {
    await Clipboard.setData(ClipboardData(text: item.originalUrl));
    if (!context.context.mounted) return;
    ScaffoldMessenger.of(
      context.context,
    ).showSnackBar(const SnackBar(content: Text('Image URL copied')));
  }
}

class ShowImageInfoAction extends ViewerAction {
  const ShowImageInfoAction();

  @override
  String get id => 'show_image_info';

  @override
  String get label => 'Image info';

  @override
  IconData get icon => Icons.info_outline_rounded;

  @override
  Future<void> execute(ViewerActionContext context, MediaItem item) async {
    final ViewerAppearancePalette palette = ViewerAppearancePalette.of(
      context.context,
    );
    final TextStyle valueStyle =
        Theme.of(context.context).textTheme.bodyMedium ??
        const TextStyle(fontSize: 14);
    final String createdAt = item.createdAt?.toIso8601String() ?? 'N/A';
    final String addedAt = item.addedAt?.toIso8601String() ?? 'N/A';

    await showModalBottomSheet<void>(
      context: context.context,
      backgroundColor: palette.sheetBackground,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Image info',
                  style: TextStyle(
                    color: palette.sheetTitleText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoLine(
                  label: 'ID',
                  value: item.id,
                  style: valueStyle,
                  primaryColor: palette.sheetPrimaryText,
                  secondaryColor: palette.sheetSecondaryText,
                ),
                _InfoLine(
                  label: 'Type',
                  value: item.type.name,
                  style: valueStyle,
                  primaryColor: palette.sheetPrimaryText,
                  secondaryColor: palette.sheetSecondaryText,
                ),
                _InfoLine(
                  label: 'Source',
                  value: item.sourceType.name,
                  style: valueStyle,
                  primaryColor: palette.sheetPrimaryText,
                  secondaryColor: palette.sheetSecondaryText,
                ),
                _InfoLine(
                  label: 'Created at',
                  value: createdAt,
                  style: valueStyle,
                  primaryColor: palette.sheetPrimaryText,
                  secondaryColor: palette.sheetSecondaryText,
                ),
                _InfoLine(
                  label: 'Added at',
                  value: addedAt,
                  style: valueStyle,
                  primaryColor: palette.sheetPrimaryText,
                  secondaryColor: palette.sheetSecondaryText,
                ),
                _InfoLine(
                  label: 'Original URL',
                  value: item.originalUrl,
                  style: valueStyle,
                  primaryColor: palette.sheetPrimaryText,
                  secondaryColor: palette.sheetSecondaryText,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PlaceholderAction extends ViewerAction {
  const PlaceholderAction();

  @override
  String get id => 'placeholder_action';

  @override
  String get label => 'More actions soon';

  @override
  IconData get icon => Icons.build_outlined;

  @override
  Future<void> execute(ViewerActionContext context, MediaItem item) async {
    ScaffoldMessenger.of(context.context).showSnackBar(
      const SnackBar(content: Text('Add your custom action here')),
    );
  }
}

class DefaultViewerActions {
  const DefaultViewerActions._();

  static List<ViewerAction> build() {
    return const <ViewerAction>[
      ShowImageInfoAction(),
      CopyImageUrlAction(),
      PlaceholderAction(),
    ];
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
    required this.style,
    required this.primaryColor,
    required this.secondaryColor,
  });

  final String label;
  final String value;
  final TextStyle style;
  final Color primaryColor;
  final Color secondaryColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: style.copyWith(color: primaryColor),
          children: [
            TextSpan(
              text: '$label: ',
              style: style.copyWith(
                color: secondaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
