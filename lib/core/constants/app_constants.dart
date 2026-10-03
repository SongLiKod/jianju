/// 应用级常量（版本、存储 key、播放倍速档位等）
class AppConstants {
  AppConstants._();

  static const String appName = '简剧';
  static const String appTagline = '纯净短剧 · 无广告';

  // ==================== 倍速档位（最高 5x，需求硬性规定） ====================
  static const List<double> playbackSpeeds = [
    0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 5.0,
  ];
  static const double defaultPlaybackSpeed = 1.0;

  // ==================== 本地存储 key（shared_preferences） ====================
  // 主题
  static const String keyThemeMode = 'settings.theme_mode'; // system/light/dark
  static const String keyPrimaryColor = 'settings.primary_color'; // 色板索引
  // 播放
  static const String keyDefaultSpeed = 'settings.default_speed';
  // 账号与设备
  static const String keyToken = 'account.token';
  static const String keyInstallId = 'device.install_id';
  static const String keyDeviceId = 'device.device_id';
  static const String keyCdid = 'device.cdid';
  static const String keyDeviceType = 'device.device_type';
  static const String keyDeviceBrand = 'device.device_brand';
  // 本地数据
  static const String keyFavorites = 'local.favorites';
  static const String keyHistory = 'local.history';

  // ==================== 本地数据限制 ====================
  /// 历史/收藏最多保留条数（防本地数据无限膨胀）
  static const int maxLocalRecords = 500;

  // ==================== 观看进度记忆 ====================
  /// 播放中保存进度的间隔
  static const Duration progressSaveInterval = Duration(seconds: 5);
  /// 开头进度小于该值不记忆
  static const Duration progressMinKeep = Duration(seconds: 3);
  /// 结尾剩余小于该值视为看完，清除记忆
  static const Duration progressEndTrim = Duration(seconds: 10);
}
