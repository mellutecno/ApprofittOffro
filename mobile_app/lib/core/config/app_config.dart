class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://mellucci.pythonanywhere.com',
  );

  static const bool googleMapsEnabled = bool.fromEnvironment(
    'GOOGLE_MAPS_ENABLED',
    defaultValue: true,
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  static const String googleAndroidClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_CLIENT_ID',
    defaultValue: '',
  );

  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: '',
  );

  static const String firebaseAppId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '',
  );

  static const String firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '',
  );

  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: '',
  );

  static const String firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: '',
  );

  static const String androidNotificationChannelId = 'approfittoffro_alerts';

  static bool get firebaseMessagingConfigured =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;
}
