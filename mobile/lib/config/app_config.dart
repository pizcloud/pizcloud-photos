// lib/config/app_config.dart
class AppConfig {
  static const String defaultServer = String.fromEnvironment('PROJECT_DEFAULT_SERVER', defaultValue: '');

  // static const String pizCloudServerUrl = String.fromEnvironment('PIZCLOUD_SERVER_URL', defaultValue: ''); // Update: deprecated

  static const bool lockServer = bool.fromEnvironment('PROJECT_LOCK_SERVER', defaultValue: true);

  static const bool showServerLabel = bool.fromEnvironment('PIZCLOUD_SHOW_SERVER_LABEL', defaultValue: false);

  static const String serverName = String.fromEnvironment('SERVER_NAME', defaultValue: 'photos');

  static const String androidPackageName = String.fromEnvironment(
    'ANDROID_PACKAGE_NAME',
    defaultValue: 'com.pizcloud.photos',
  );

  static const double minReferralWithdrawAmount = 5.0;

  static const String serverClientId = '68363837894-ukp9akn9uujb481sgpubbt9nq8s9c843.apps.googleusercontent.com';
  static const String accountServiceBase = 'https://account.pizcloud.com/api';

  static const String accountHost = 'account.pizcloud.com';
  static const String service = 'app_photos';
}
