// lib/config/app_config.dart
class AppConfig {
  static const String defaultServer = String.fromEnvironment('PROJECT_DEFAULT_SERVER', defaultValue: '');

  static const String pizCloudServerUrl = String.fromEnvironment('PIZCLOUD_SERVER_URL', defaultValue: '');

  static const bool lockServer = bool.fromEnvironment('PROJECT_LOCK_SERVER', defaultValue: false);

  static const bool showServerLabel = bool.fromEnvironment('IMMICH_SHOW_SERVER_LABEL', defaultValue: false);
}
