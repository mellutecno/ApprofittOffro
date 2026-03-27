class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://mellucci.pythonanywhere.com',
  );

  static const bool googleMapsEnabled = bool.fromEnvironment(
    'GOOGLE_MAPS_ENABLED',
    defaultValue: false,
  );
}
