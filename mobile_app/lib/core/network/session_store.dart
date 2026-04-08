import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  static const _cookieKey = 'approfittoffro_cookie';
  static const _lastActiveAtKey = 'approfittoffro_last_active_at';

  Future<String?> loadCookie() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cookieKey);
  }

  Future<void> saveCookie(String cookie) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cookieKey, cookie);
  }

  Future<DateTime?> loadLastActiveAt() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_lastActiveAtKey);
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> saveLastActiveAt(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastActiveAtKey, value.millisecondsSinceEpoch);
  }

  Future<void> touch() async {
    await saveLastActiveAt(DateTime.now());
  }

  Future<bool> isSessionExpired(Duration timeout) async {
    final lastActiveAt = await loadLastActiveAt();
    if (lastActiveAt == null) {
      return false;
    }
    return DateTime.now().difference(lastActiveAt) >= timeout;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cookieKey);
    await prefs.remove(_lastActiveAtKey);
  }
}
