import 'package:flutter/material.dart';

enum ViewerAppearanceMode { system, light, dark }

/// Global appearance configuration for viewer screens.
///
/// Default is [ViewerAppearanceMode.system] so viewer follows OS brightness.
class ViewerAppearanceConfig {
  static const ViewerAppearanceMode themeMode = ViewerAppearanceMode.system;
}

@immutable
class ViewerAppearancePalette {
  const ViewerAppearancePalette({
    required this.brightness,
    required this.scaffoldBackground,
    required this.appBarBackground,
    required this.appBarForeground,
    required this.overlayBackdropBase,
    required this.emptyStateText,
    required this.mediaBackground,
    required this.menuPopupBackground,
    required this.menuPopupItemText,
    required this.sheetBackground,
    required this.sheetTitleText,
    required this.sheetPrimaryText,
    required this.sheetSecondaryText,
    required this.videoPlaceholderIcon,
    required this.videoPlaceholderText,
    required this.errorPlaceholderIcon,
    required this.errorPlaceholderText,
    // new
    required this.overlayControlForeground,
    required this.overlayControlDisabledForeground,
    // `overlayTopScrimStart`, `overlayTopScrimEnd`,
    // `overlayBottomScrimStart`, `overlayBottomScrimEnd`,
    // `overlayButtonBackground`
    // New floating-controls fields:
    required this.overlayChipBackground,
    required this.overlayChipBorder,
    required this.overlayChipShadow,
    required this.overlayChipStrongShadow,
    required this.videoControlsPanelBackground,
    // #new
  });

  final Brightness brightness;
  final Color scaffoldBackground;
  final Color appBarBackground;
  final Color appBarForeground;
  final Color overlayBackdropBase;
  final Color emptyStateText;
  final Color mediaBackground;
  final Color menuPopupBackground;
  final Color menuPopupItemText;
  final Color sheetBackground;
  final Color sheetTitleText;
  final Color sheetPrimaryText;
  final Color sheetSecondaryText;
  final Color videoPlaceholderIcon;
  final Color videoPlaceholderText;
  final Color errorPlaceholderIcon;
  final Color errorPlaceholderText;
  // new
  final Color overlayControlForeground;
  final Color overlayControlDisabledForeground;
  final Color overlayChipBackground;
  final Color overlayChipBorder;
  final Color overlayChipShadow;
  final Color overlayChipStrongShadow;
  final Color videoControlsPanelBackground;
  // #new

  static const ViewerAppearancePalette _light = ViewerAppearancePalette(
    brightness: Brightness.light,
    scaffoldBackground: Color(0xFFF6F7FB),
    appBarBackground: Color(0xFFF6F7FB),
    appBarForeground: Color(0xFF101217),
    overlayBackdropBase: Color(0xFFF6F7FB),
    emptyStateText: Color(0x99000000),
    mediaBackground: Color(0xFFF6F7FB),
    menuPopupBackground: Colors.white,
    menuPopupItemText: Color(0xDE000000),
    sheetBackground: Colors.white,
    sheetTitleText: Color(0xDE000000),
    sheetPrimaryText: Color(0xDE000000),
    sheetSecondaryText: Color(0x99000000),
    videoPlaceholderIcon: Color(0x99000000),
    videoPlaceholderText: Color(0x99000000),
    errorPlaceholderIcon: Color(0x80000000),
    errorPlaceholderText: Color(0x99000000),
    // new
    overlayControlForeground: Colors.white,
    overlayControlDisabledForeground: Color(0x99FFFFFF),
    overlayChipBackground: Color(0x47000000),
    overlayChipBorder: Color(0x5CFFFFFF),
    overlayChipShadow: Color(0x66000000),
    overlayChipStrongShadow: Color(0x94000000),
    videoControlsPanelBackground: Color(0x59000000),
    // #new
  );

  static const ViewerAppearancePalette _dark = ViewerAppearancePalette(
    brightness: Brightness.dark,
    scaffoldBackground: Colors.black,
    appBarBackground: Colors.black,
    appBarForeground: Colors.white,
    overlayBackdropBase: Colors.black,
    emptyStateText: Colors.white70,
    mediaBackground: Colors.black,
    menuPopupBackground: Color(0xFF1E1E1E),
    menuPopupItemText: Color(0xF2FFFFFF),
    sheetBackground: Color(0xFF1E1E1E),
    sheetTitleText: Colors.white,
    sheetPrimaryText: Colors.white,
    sheetSecondaryText: Colors.white70,
    videoPlaceholderIcon: Colors.white70,
    videoPlaceholderText: Color(0xB3FFFFFF),
    errorPlaceholderIcon: Colors.white60,
    errorPlaceholderText: Colors.white70,
    // new
    overlayControlForeground: Colors.white,
    overlayControlDisabledForeground: Color(0x99FFFFFF),
    overlayChipBackground: Color(0x40000000),
    overlayChipBorder: Color(0x4DFFFFFF),
    overlayChipShadow: Color(0x66000000),
    overlayChipStrongShadow: Color(0x8A000000),
    videoControlsPanelBackground: Color(0x4D000000),
    // #new
  );

  static ViewerAppearancePalette of(
    BuildContext context, {
    ViewerAppearanceMode? mode,
  }) {
    final ViewerAppearanceMode resolvedMode =
        mode ?? ViewerAppearanceConfig.themeMode;
    final Brightness brightness = switch (resolvedMode) {
      ViewerAppearanceMode.system => _systemBrightness(context),
      ViewerAppearanceMode.light => Brightness.light,
      ViewerAppearanceMode.dark => Brightness.dark,
    };
    return brightness == Brightness.dark ? _dark : _light;
  }

  static Brightness _systemBrightness(BuildContext context) {
    final MediaQueryData? media = MediaQuery.maybeOf(context);
    if (media != null) return media.platformBrightness;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }
}
