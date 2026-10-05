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

  // ==================== 播放体验（预载 / 缓冲 / 进度条） ====================
  static bool _boolOf(String key, bool fallback) {
    final raw = StorageService.getString(key);
    if (raw.isEmpty) return fallback;
    return raw == '1';
  }

  static Future<void> _setBool(String key, bool v) =>
      StorageService.setString(key, v ? '1' : '0');

  static int _intOf(String key, List<int> options, int fallback) {
    final v = int.tryParse(StorageService.getString(key));
    return v != null && options.contains(v) ? v : fallback;
  }

  /// 预载下一集（本集结尾前提前解析下一集直链，换集秒开）
  static bool get preloadNext =>
      _boolOf(AppConstants.keyPreloadNext, AppConstants.defaultPreloadNext);

  static Future<void> setPreloadNext(bool v) =>
      _setBool(AppConstants.keyPreloadNext, v);

  /// 预载提前量（距结尾的秒数）
  static int get preloadLeadSec => _intOf(AppConstants.keyPreloadLead,
      AppConstants.preloadLeadOptions, AppConstants.defaultPreloadLeadSec);

  static Future<void> setPreloadLeadSec(int v) =>
      StorageService.setString(AppConstants.keyPreloadLead, '$v');

  /// 网络缓冲秒数（mpv cache-secs + 跨集预缓存预算）。
  /// 自定义分钟数（×60，60~3600）不在预设列表内，故按范围校验、不按列表
  /// 校验，否则重启后会读回默认值（曾导致自定义 5 分钟重启后变 20 秒）
  static int get bufferSecs {
    final v = int.tryParse(StorageService.getString(AppConstants.keyBufferSecs));
    if (v == null || v < 1 || v > 3600) return AppConstants.defaultBufferSecs;
    return v;
  }

  static Future<void> setBufferSecs(int v) =>
      StorageService.setString(AppConstants.keyBufferSecs, '$v');

  /// 底部细进度条常显开关
  static bool get slimProgress =>
      _boolOf(AppConstants.keySlimProgress, AppConstants.defaultSlimProgress);

  static Future<void> setSlimProgress(bool v) =>
      _setBool(AppConstants.keySlimProgress, v);

  // ==================== 搜索 ====================
  /// 跨站搜索合并后展示的条数（默认 10 条）
  static int get searchLimit {
    final v = int.tryParse(StorageService.getString(AppConstants.keySearchLimit));
    if (v == null || !AppConstants.searchLimitOptions.contains(v)) {
      return AppConstants.defaultSearchLimit;
    }
    return v;
  }

  static Future<void> setSearchLimit(int v) =>
      StorageService.setString(AppConstants.keySearchLimit, '$v');

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

  // ==================== 自定义站点（JSON 数组原始串） ====================
  static String get customLinesRaw =>
      StorageService.getString(AppConstants.keyCustomLines);

  static Future<void> setCustomLinesRaw(String raw) =>
      StorageService.setString(AppConstants.keyCustomLines, raw);
}
