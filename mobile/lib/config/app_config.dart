// lib/config/app_config.dart
class AppConfig {
  static const String defaultServer = String.fromEnvironment('PROJECT_DEFAULT_SERVER', defaultValue: '');

  static const String pizCloudServerUrl = String.fromEnvironment('PIZCLOUD_SERVER_URL', defaultValue: '');

  static const bool lockServer = bool.fromEnvironment('PROJECT_LOCK_SERVER', defaultValue: false);

  static const bool showServerLabel = bool.fromEnvironment('PIZCLOUD_SHOW_SERVER_LABEL', defaultValue: false);

  static const double minReferralWithdrawAmount = 5.0;

  static const String serverClientId = '118511362569-l7qp3v9b61ce6jpteg58pn38gviuam7v.apps.googleusercontent.com';
  static const String accountServiceBase = 'https://account.photocloudbox.com/api';
  static const String photosServiceBase = 'https://photos.photocloudbox.com/api';
}
