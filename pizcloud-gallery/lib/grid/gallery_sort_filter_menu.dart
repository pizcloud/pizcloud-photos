import 'package:flutter/material.dart';

import 'grid_appearance_config.dart';

enum GallerySortMode { createdAtDesc, addedAtDesc }

// new
@immutable
class GallerySortFilterMenuTexts {
  const GallerySortFilterMenuTexts({
    required this.tooltipSortFilter,
    required this.sectionSort,
    required this.optionCreatedTime,
    required this.optionAddedTime,
    required this.sectionFilter,
    required this.optionShowAll,
    required this.sectionMediaType,
    required this.optionPhotos,
    required this.optionVideos,
    required this.sectionStorage,
    required this.optionOnDevice,
    required this.optionCloud,
  });

  const GallerySortFilterMenuTexts.defaults()
    : tooltipSortFilter = 'Sort & filter',
      sectionSort = 'Sort',
      optionCreatedTime = 'Created time',
      optionAddedTime = 'Added time',
      sectionFilter = 'Filter',
      optionShowAll = 'Show all',
      sectionMediaType = 'Media type',
      optionPhotos = 'Photos',
      optionVideos = 'Videos',
      sectionStorage = 'Storage',
      optionOnDevice = 'On device',
      optionCloud = 'Cloud';

  final String tooltipSortFilter;
  final String sectionSort;
  final String optionCreatedTime;
  final String optionAddedTime;
  final String sectionFilter;
  final String optionShowAll;
  final String sectionMediaType;
  final String optionPhotos;
  final String optionVideos;
  final String sectionStorage;
  final String optionOnDevice;
  final String optionCloud;
}
// #new

class GalleryFilterSelection {
  const GalleryFilterSelection({
    required this.includePhotos,
    required this.includeVideos,
    required this.includeOnDevice,
    required this.includeCloud,
  });

  const GalleryFilterSelection.all()
    : includePhotos = true,
      includeVideos = true,
      includeOnDevice = true,
      includeCloud = true;

  final bool includePhotos;
  final bool includeVideos;
  final bool includeOnDevice;
  final bool includeCloud;

  GalleryFilterSelection copyWith({
    bool? includePhotos,
    bool? includeVideos,
    bool? includeOnDevice,
    bool? includeCloud,
  }) {
    return GalleryFilterSelection(
      includePhotos: includePhotos ?? this.includePhotos,
      includeVideos: includeVideos ?? this.includeVideos,
      includeOnDevice: includeOnDevice ?? this.includeOnDevice,
      includeCloud: includeCloud ?? this.includeCloud,
    );
  }

  bool get isAll =>
      includePhotos && includeVideos && includeOnDevice && includeCloud;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GalleryFilterSelection &&
        other.includePhotos == includePhotos &&
        other.includeVideos == includeVideos &&
        other.includeOnDevice == includeOnDevice &&
        other.includeCloud == includeCloud;
  }

  @override
  int get hashCode =>
      Object.hash(includePhotos, includeVideos, includeOnDevice, includeCloud);
}

enum GalleryMenuAction {
  sortCreatedAt,
  sortAddedAt,
  filterReset,
  filterTogglePhoto,
  filterToggleVideo,
  filterToggleOnDevice,
  filterToggleCloud,
}

class GallerySortFilterMenuButton extends StatelessWidget {
  const GallerySortFilterMenuButton({
    super.key,
    required this.sortMode,
    required this.filterSelection,
    required this.onSelected,
    this.texts = const GallerySortFilterMenuTexts.defaults(), // new
  });

  final GallerySortMode sortMode;
  final GalleryFilterSelection filterSelection;
  final ValueChanged<GalleryMenuAction> onSelected;
  final GallerySortFilterMenuTexts texts; // new
  static const EdgeInsets _itemPadding = EdgeInsets.symmetric(horizontal: 10);
  static const double _itemHeight = 45;
  static const double _sectionHeight = 24;

  @override
  Widget build(BuildContext context) {
    // new
    // final GridAppearancePalette palette = GridAppearancePalette.of(context);
    final Brightness currentAppBrightness = Theme.of(context).brightness;
    final GridAppearancePalette palette = GridAppearancePalette.of(
      context,
      mode: currentAppBrightness == Brightness.dark
          ? GridAppearanceMode.dark
          : GridAppearanceMode.light,
    );
    // #new
    final bool showAllSelected = filterSelection.isAll;
    return Material(
      color: palette.menuButtonBackground,
      shape: const CircleBorder(),
      child: PopupMenuButton<GalleryMenuAction>(
        // tooltip: 'Sort & filter', // new
        tooltip: texts.tooltipSortFilter, // new
        padding: EdgeInsets.zero,
        color: palette.popupMenuBackground,
        // icon: Icon(Icons.more_horiz_rounded, color: palette.menuButtonIcon), // new
        // icon: Icon(Icons.tune_rounded, color: resolvedMenuButtonIcon), // new
        icon: Icon(Icons.tune_rounded, color: palette.menuButtonIcon), // new
        onSelected: onSelected,
        itemBuilder: (context) {
          return <PopupMenuEntry<GalleryMenuAction>>[
            PopupMenuItem<GalleryMenuAction>(
              enabled: false,
              height: _sectionHeight,
              padding: _itemPadding,
              child: Text(
                // 'Sort', // new
                texts.sectionSort, // new
                style: TextStyle(color: palette.popupMenuSectionText),
              ),
            ),
            _buildActionItem(
              value: GalleryMenuAction.sortCreatedAt,
              // label: 'Created time', // new
              label: texts.optionCreatedTime, // new
              checked: sortMode == GallerySortMode.createdAtDesc,
              textColor: palette.popupMenuItemText,
              checkColor: palette.popupMenuItemText,
            ),
            _buildActionItem(
              value: GalleryMenuAction.sortAddedAt,
              // label: 'Added time', // new
              label: texts.optionAddedTime, // new
              checked: sortMode == GallerySortMode.addedAtDesc,
              textColor: palette.popupMenuItemText,
              checkColor: palette.popupMenuItemText,
            ),
            const PopupMenuDivider(height: 8),
            PopupMenuItem<GalleryMenuAction>(
              enabled: false,
              height: _sectionHeight,
              padding: _itemPadding,
              child: Text(
                // 'Filter', // new
                texts.sectionFilter, // new
                style: TextStyle(color: palette.popupMenuSectionText),
              ),
            ),
            _buildActionItem(
              value: GalleryMenuAction.filterReset,
              // label: 'Show all', // new
              label: texts.optionShowAll, // new
              checked: filterSelection.isAll,
              textColor: palette.popupMenuItemText,
              checkColor: palette.popupMenuItemText,
            ),
            PopupMenuItem<GalleryMenuAction>(
              enabled: false,
              height: _sectionHeight,
              padding: _itemPadding,
              child: Text(
                // 'Media type',
                texts.sectionMediaType, // new
                style: TextStyle(color: palette.popupMenuSectionText),
              ),
            ),
            _buildActionItem(
              value: GalleryMenuAction.filterTogglePhoto,
              // label: 'Photos',
              label: texts.optionPhotos, // new
              checked: !showAllSelected && filterSelection.includePhotos,
              textColor: palette.popupMenuItemText,
              checkColor: palette.popupMenuItemText,
            ),
            _buildActionItem(
              value: GalleryMenuAction.filterToggleVideo,
              // label: 'Videos',
              label: texts.optionVideos, // new
              checked: !showAllSelected && filterSelection.includeVideos,
              textColor: palette.popupMenuItemText,
              checkColor: palette.popupMenuItemText,
            ),
            PopupMenuItem<GalleryMenuAction>(
              enabled: false,
              height: _sectionHeight,
              padding: _itemPadding,
              child: Text(
                // 'Storage',
                texts.sectionStorage, // new
                style: TextStyle(color: palette.popupMenuSectionText),
              ),
            ),
            _buildActionItem(
              value: GalleryMenuAction.filterToggleOnDevice,
              // label: 'On device',
              label: texts.optionOnDevice, // new
              checked: !showAllSelected && filterSelection.includeOnDevice,
              textColor: palette.popupMenuItemText,
              checkColor: palette.popupMenuItemText,
            ),
            _buildActionItem(
              value: GalleryMenuAction.filterToggleCloud,
              // label: 'Cloud',
              label: texts.optionCloud, // new
              checked: !showAllSelected && filterSelection.includeCloud,
              textColor: palette.popupMenuItemText,
              checkColor: palette.popupMenuItemText,
            ),
          ];
        },
      ),
    );
  }

  PopupMenuItem<GalleryMenuAction> _buildActionItem({
    required GalleryMenuAction value,
    required String label,
    required bool checked,
    required Color textColor,
    required Color checkColor,
  }) {
    return PopupMenuItem<GalleryMenuAction>(
      value: value,
      height: _itemHeight,
      padding: _itemPadding,
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: checked
                ? Icon(Icons.check, size: 14, color: checkColor)
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: textColor)),
        ],
      ),
    );
  }
}
