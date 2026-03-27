class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://mellucci.pythonanywhere.com',
  );

  static const bool googleMapsEnabled = bool.fromEnvironment(
    'GOOGLE_MAPS_ENABLED',
    defaultValue: false,
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  static const String googleAndroidClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_CLIENT_ID',
    defaultValue: '',
  );
}
