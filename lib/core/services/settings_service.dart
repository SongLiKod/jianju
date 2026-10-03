import '../constants/app_constants.dart';
import 'storage_service.dart';

/// 全局设置持久化（主题 / 默认倍速）
///
/// 所有用户可修改配置统一收纳在【设置界面】，全局默认值以设置页为准。
class SettingsService {
  SettingsService._();

  // ==================== 主题：明暗模式 ====================
  static String get themeMode =>
      StorageService.getString(AppConstants.keyThemeMode, fallback: 'system');

  static Future<void> setThemeMode(String mode) =>
      StorageService.setString(AppConstants.keyThemeMode, mode);

  // ==================== 主题：自定义主色（色板索引） ====================
  static int get primaryColorIndex {
    final raw = StorageService.getString(AppConstants.keyPrimaryColor);
    return int.tryParse(raw) ?? 0;
  }

  static Future<void> setPrimaryColorIndex(int index) =>
      StorageService.setString(AppConstants.keyPrimaryColor, '$index');

  // ==================== 播放器全局默认倍速 ====================
  static double get defaultSpeed {
    final raw = StorageService.getString(AppConstants.keyDefaultSpeed);
    final v = double.tryParse(raw);
    if (v != null && AppConstants.playbackSpeeds.contains(v)) return v;
    return AppConstants.defaultPlaybackSpeed;
  }

  static Future<void> setDefaultSpeed(double speed) =>
      StorageService.setString(AppConstants.keyDefaultSpeed, '$speed');
}
