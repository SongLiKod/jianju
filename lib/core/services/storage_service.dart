import 'package:shared_preferences/shared_preferences.dart';

/// shared_preferences 单例（所有本地配置/数据统一走这里）
class StorageService {
  StorageService._();

  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get prefs => _prefs;

  static String getString(String key, {String fallback = ''}) =>
      _prefs.getString(key) ?? fallback;

  static Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  static Future<void> remove(String key) => _prefs.remove(key);
}
