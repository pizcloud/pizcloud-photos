import 'package:flutter/material.dart';
import 'package:pizcloud_gallery/grid/media_item.dart';

import 'viewer_appearance_config.dart';
import 'viewer_action.dart';

class ViewerActionMenu extends StatelessWidget {
  const ViewerActionMenu({
    super.key,
    required this.actions,
    required this.item,
    required this.onSelected,
    this.iconColor, // new
    this.iconBackgroundColor, // new
    this.iconBorderColor, // new
    this.iconShadowColor, // new
  });

  final List<ViewerAction> actions;
  final MediaItem item;
  final ValueChanged<ViewerAction> onSelected;
  final Color? iconColor; // new
  final Color? iconBackgroundColor; // new
  final Color? iconBorderColor; // new
  final Color? iconShadowColor; // new

  @override
  Widget build(BuildContext context) {
    final ViewerAppearancePalette palette = ViewerAppearancePalette.of(context);
    final List<ViewerAction> visibleActions = actions
        .where((action) => action.isVisible(item))
        .toList(growable: false);

    if (visibleActions.isEmpty) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<ViewerAction>(
      tooltip: 'Image menu',
      padding: EdgeInsets.zero,
      // new
      icon: SizedBox(
        width: 40,
        height: 40,
        child: DecoratedBox(
          // Old behavior rendered a bare icon with no background shape.
          decoration: iconBackgroundColor == null
              ? const BoxDecoration(shape: BoxShape.circle)
              : BoxDecoration(
                  color: iconBackgroundColor,
                  shape: BoxShape.circle,
                  // new
                  border: iconBorderColor == null
                      ? null
                      : Border.all(color: iconBorderColor!),
                  boxShadow: iconShadowColor == null
                      ? null
                      : <BoxShadow>[
                          BoxShadow(
                            color: iconShadowColor!,
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                  // #new
                ),
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, -1),
              child: Icon(
                Icons.more_horiz_rounded,
                color: iconColor ?? palette.appBarForeground,
              ),
            ),
          ),
        ),
      ),
      // #new
      color: palette.menuPopupBackground,
      onSelected: onSelected,
      itemBuilder: (context) {
        return visibleActions
            .map((action) {
              return PopupMenuItem<ViewerAction>(
                value: action,
                child: Row(
                  children: [
                    Icon(
                      action.icon,
                      size: 18,
                      color: palette.menuPopupItemText,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      action.label,
                      style: TextStyle(color: palette.menuPopupItemText),
                    ),
                  ],
                ),
              );
            })
            .toList(growable: false);
      },
    );
  }
}
