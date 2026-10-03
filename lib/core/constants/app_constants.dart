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
  // 数据源
  static const String keyDataSource = 'settings.data_source'; // web/api52/line:<id>
  static const String keyApi52Key = 'settings.api52_key';
  // 播放线路
  static const String keyPinnedLine = 'settings.pinned_line'; // ''=自动（最快）
  static const String keyPlayLineStats = 'local.play_line_stats'; // 线路测速统计 JSON

  // ==================== 数据源 ====================
  /// 数据源：官方网页源（默认，前 3 集可播）
  static const String dataSourceWeb = 'web';
  /// 数据源：52api 红果源（全集，需 apikey）
  static const String dataSourceApi52 = 'api52';

  /// 数据源前缀：整站数据源（`line:<线路id>`，首页/分类/搜索/详情/播放全走该站）
  static const String dataSourceLinePrefix = 'line:';

  /// 整站数据源数据源 id：`line:<线路id>` → 线路 id（非整站源返回空串）
  static String dataSourceLineId(String dataSource) =>
      dataSource.startsWith(dataSourceLinePrefix)
          ? dataSource.substring(dataSourceLinePrefix.length)
          : '';

  /// 生成整站数据源 id
  static String dataSourceOfLine(String lineId) => '$dataSourceLinePrefix$lineId';

  static const String api52BaseUrl = 'https://www.52api.cn/api/hg_duanju';
  static const String api52DocUrl = 'https://www.52api.cn';
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
