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

  // ==================== 数据源 ====================
  /// 数据源：`web` 官方网页源 / `api52` 第三方红果聚合源 /
  /// `line:<线路id>` 整站数据源（该站的首页/分类/搜索/详情/播放全部数据）
  static String get dataSource {
    final raw = StorageService.getString(AppConstants.keyDataSource);
    if (raw == AppConstants.dataSourceApi52 ||
        raw == AppConstants.dataSourceWeb) {
      return raw;
    }
    if (raw.startsWith(AppConstants.dataSourceLinePrefix)) {
      final lineId = AppConstants.dataSourceLineId(raw);
      if (lineId.isNotEmpty) return raw;
    }
    return AppConstants.dataSourceWeb;
  }

  static Future<void> setDataSource(String source) =>
      StorageService.setString(AppConstants.keyDataSource, source);

  static String get apiKey52 =>
      StorageService.getString(AppConstants.keyApi52Key).trim();

  static Future<void> setApiKey52(String key) =>
      StorageService.setString(AppConstants.keyApi52Key, key.trim());

  // ==================== 播放线路 ====================
  /// 手动锁定的线路 id（空串 = 自动选择最快线路）
  static String get pinnedLineId =>
      StorageService.getString(AppConstants.keyPinnedLine);

  static Future<void> setPinnedLine(String lineId) =>
      StorageService.setString(AppConstants.keyPinnedLine, lineId.trim());
}
