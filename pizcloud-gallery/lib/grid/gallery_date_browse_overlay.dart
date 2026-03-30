import 'package:flutter/material.dart';

import 'grid_appearance_config.dart';

enum GalleryDateBrowseMode { all, year, month }

@immutable
class GalleryDateBrowseTexts {
  const GalleryDateBrowseTexts({
    required this.optionAll,
    required this.optionYear,
    required this.optionMonth,
  });

  const GalleryDateBrowseTexts.defaults()
    : optionAll = 'All',
      optionYear = 'Year',
      optionMonth = 'Month';

  final String optionAll;
  final String optionYear;
  final String optionMonth;
}

class GalleryDateBrowseOverlay extends StatelessWidget {
  const GalleryDateBrowseOverlay({
    super.key,
    required this.mode,
    required this.texts,
    required this.onModeChanged,
    this.yearButtonKey,
    this.monthButtonKey,
    this.onYearTapped,
    this.onMonthTapped,
  });

  final GalleryDateBrowseMode mode;
  final GalleryDateBrowseTexts texts;
  final ValueChanged<GalleryDateBrowseMode> onModeChanged;
  final Key? yearButtonKey;
  final Key? monthButtonKey;
  final VoidCallback? onYearTapped;
  final VoidCallback? onMonthTapped;

  @override
  Widget build(BuildContext context) {
    final Brightness currentAppBrightness = Theme.of(context).brightness;
    final GridAppearancePalette palette = GridAppearancePalette.of(
      context,
      mode: currentAppBrightness == Brightness.dark
          ? GridAppearanceMode.dark
          : GridAppearanceMode.light,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.fpsBadgeBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildModeButton(
              context: context,
              label: texts.optionAll,
              value: GalleryDateBrowseMode.all,
              palette: palette,
            ),
            const SizedBox(width: 4),
            _buildModeButton(
              context: context,
              label: texts.optionYear,
              value: GalleryDateBrowseMode.year,
              palette: palette,
              buttonKey: yearButtonKey,
            ),
            const SizedBox(width: 4),
            _buildModeButton(
              context: context,
              label: texts.optionMonth,
              value: GalleryDateBrowseMode.month,
              palette: palette,
              buttonKey: monthButtonKey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required BuildContext context,
    required String label,
    required GalleryDateBrowseMode value,
    required GridAppearancePalette palette,
    Key? buttonKey,
  }) {
    final bool selected = mode == value;
    final Color selectedBackground = palette.fpsBadgeText.withValues(
      alpha: 0.16,
    );
    final Color selectedBorder = palette.fpsBadgeText.withValues(alpha: 0.28);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (value == GalleryDateBrowseMode.year) {
            onYearTapped?.call();
          } else if (value == GalleryDateBrowseMode.month) {
            onMonthTapped?.call();
          }
          onModeChanged(value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? selectedBackground : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? selectedBorder : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.fpsBadgeText,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}
