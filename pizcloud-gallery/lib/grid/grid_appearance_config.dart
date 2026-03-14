import 'package:flutter/material.dart';

enum GridAppearanceMode { system, light, dark }

/// Global grid appearance configuration.
///
/// Change [themeMode] to `GridAppearanceMode.light` or
/// `GridAppearanceMode.dark` to force a mode.
class GridAppearanceConfig {
  static const GridAppearanceMode themeMode = GridAppearanceMode.system;
}

@immutable
class GridAppearancePalette {
  const GridAppearancePalette({
    required this.brightness,
    required this.gridBackground,
    required this.cellBackground,
    required this.cellErrorBackground,
    required this.placeholderText,
    required this.mediaOverlayIcon,
    required this.indexBadgeBackground,
    required this.indexBadgeText,
    required this.menuButtonBackground,
    required this.menuButtonIcon,
    required this.popupMenuBackground,
    required this.popupMenuItemText,
    required this.popupMenuSectionText,
    required this.fpsBadgeBackground,
    required this.fpsBadgeText,
  });

  final Brightness brightness;
  final Color gridBackground;
  final Color cellBackground;
  final Color cellErrorBackground;
  final Color placeholderText;
  final Color mediaOverlayIcon;
  final Color indexBadgeBackground;
  final Color indexBadgeText;
  final Color menuButtonBackground;
  final Color menuButtonIcon;
  final Color popupMenuBackground;
  final Color popupMenuItemText;
  final Color popupMenuSectionText;
  final Color fpsBadgeBackground;
  final Color fpsBadgeText;

  static const GridAppearancePalette _light = GridAppearancePalette(
    brightness: Brightness.light,
    gridBackground: Color(0xFFF6F7FB),
    cellBackground: Color(0xFFE5E7ED),
    cellErrorBackground: Color(0xFFD7DAE2),
    placeholderText: Color(0x8A000000),
    mediaOverlayIcon: Colors.white,
    indexBadgeBackground: Color(0x8A000000),
    indexBadgeText: Colors.white,
    menuButtonBackground: Color(0x8A000000),
    menuButtonIcon: Colors.white,
    popupMenuBackground: Colors.white,
    popupMenuItemText: Color(0xDE000000),
    popupMenuSectionText: Color(0x99000000),
    fpsBadgeBackground: Color(0xB3000000),
    fpsBadgeText: Colors.white,
  );

  static const GridAppearancePalette _dark = GridAppearancePalette(
    brightness: Brightness.dark,
    gridBackground: Color(0xFF101216),
    cellBackground: Color(0xFF22252E),
    cellErrorBackground: Color(0xFF2E3340),
    placeholderText: Color(0xB3FFFFFF),
    mediaOverlayIcon: Colors.white,
    indexBadgeBackground: Color(0xB3000000),
    indexBadgeText: Colors.white,
    menuButtonBackground: Color(0x66FFFFFF),
    menuButtonIcon: Colors.white,
    popupMenuBackground: Color(0xFF1A1E27),
    popupMenuItemText: Color(0xF2FFFFFF),
    popupMenuSectionText: Color(0x99FFFFFF),
    fpsBadgeBackground: Color(0xCC000000),
    fpsBadgeText: Colors.white,
  );

  static GridAppearancePalette of(
    BuildContext context, {
    GridAppearanceMode? mode,
  }) {
    final GridAppearanceMode resolvedMode =
        mode ?? GridAppearanceConfig.themeMode;
    final Brightness brightness = switch (resolvedMode) {
      GridAppearanceMode.system => _systemBrightness(context),
      GridAppearanceMode.light => Brightness.light,
      GridAppearanceMode.dark => Brightness.dark,
    };
    return brightness == Brightness.dark ? _dark : _light;
  }

  static Brightness _systemBrightness(BuildContext context) {
    final MediaQueryData? media = MediaQuery.maybeOf(context);
    if (media != null) return media.platformBrightness;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }
}
