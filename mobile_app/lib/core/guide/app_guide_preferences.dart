import 'package:shared_preferences/shared_preferences.dart';

class AppGuidePreferences {
  const AppGuidePreferences._();

  static const int currentVersion = 5;
  static const String _hiddenVersionKey = 'app_guide_hidden_version';

  static Future<bool> shouldShowAtStartup({int? guideVersion}) async {
    final prefs = await SharedPreferences.getInstance();
    final hiddenVersion = prefs.getInt(_hiddenVersionKey) ?? 0;
    return hiddenVersion < (guideVersion ?? currentVersion);
  }

  static Future<void> hideCurrentVersionAtStartup({int? guideVersion}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hiddenVersionKey, guideVersion ?? currentVersion);
  }
}
