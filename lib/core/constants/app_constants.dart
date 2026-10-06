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
  // 播放体验（预载/缓冲/进度条）
  static const String keyPreloadNext = 'settings.preload_next';
  static const String keyPreloadLead = 'settings.preload_lead_sec';
  static const String keyBufferSecs = 'settings.buffer_secs';
  static const String keySlimProgress = 'settings.slim_progress';
  // 清晰度（详见 docs/简剧 - 清晰度增强方案.md）
  static const String keyLineQualityFirst = 'settings.line_quality_first';
  // 数据源
  static const String keyDataSource = 'settings.data_source'; // web/api52/line:<id>
  static const String keyApi52Key = 'settings.api52_key';
  // 搜索
  static const String keySearchLimit = 'settings.search_limit'; // 结果条数
  // 播放线路
  static const String keyPinnedLine = 'settings.pinned_line'; // ''=自动（最快）
  static const String keyPlayLineStats = 'local.play_line_stats'; // 线路测速统计 JSON
  static const String keyCustomLines = 'local.custom_lines'; // 自定义站点 JSON

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
  static const String keySearchHistory = 'local.search_history';

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

  // ==================== 播放体验（预载 / 缓冲 / 进度条） ====================
  /// 预载下一集默认开关
  static const bool defaultPreloadNext = true;
  /// 距结尾多少秒开始预载下一集（默认 10 秒）
  static const int defaultPreloadLeadSec = 10;
  /// 预载提前量候选项（秒）
  static const List<int> preloadLeadOptions = [5, 10, 15, 30, 60];
  /// 网络缓冲默认秒数（mpv cache-secs）
  static const int defaultBufferSecs = 20;
  /// 缓冲档位候选项（秒）：小 / 标准 / 大 / 超大
  static const List<int> bufferOptions = [10, 20, 60, 180];
  /// 底部细进度条默认开启
  static const bool defaultSlimProgress = true;

  // ==================== 清晰度（路径 A） ====================
  /// 路径 A：清晰度优先选线路（后台探测各线路码率，播放时按码率排序）
  static const bool defaultLineQualityFirst = true;
  /// 未探测到码率的线路在排序中的占位值（kbps）。
  /// 实测各源码率 469~1102，取中位偏上：首播全部未知时彼此相等，
  /// 退化为纯耗时排序（与未开启本功能时行为一致）。
  static const int unknownBitrateKbps = 800;
  /// 码率探测结果的持久化 key（线路统计 JSON 内，单位 kbps，0=探测失败）
  static const String statBitrateKey = 'br';

  // ==================== 搜索历史 ====================
  /// 搜索历史最多保留条数
  static const int maxSearchHistory = 20;

  // ==================== 搜索结果 ====================
  /// 跨站搜索合并后默认展示条数
  static const int defaultSearchLimit = 10;
  /// 搜索结果条数候选项（设置 → 搜索 → 搜索结果条数）
  static const List<int> searchLimitOptions = [10, 20, 30, 50, 100];

  // ==================== 使用声明（关于页「使用声明」全文） ====================
  static const String usageStatement = '''
本软件为个人兴趣爱好开发产物，仅供个人学习、娱乐、非商业性质免费使用。

本人对本软件享有全部合法知识产权，未经作者本人书面许可，任何单位及个人不得对本软件进行二次开发、修改、复刻、衍生创作，不得将本软件及相关资源用于商业盈利、引流变现、付费售卖等一切牟利行为，严禁任何违规商用、二次开发及非法传播行为。

本软件无任何商业用途及商业服务属性，使用者在使用本软件的过程中，需自觉遵守当地法律法规及网络使用规范。因违规使用、私自篡改软件内容、非法商用、不当操作软件所造成的一切直接或间接损失、法律责任、纠纷风险等，均由使用者本人自行承担，软件作者不承担任何连带法律责任与相关后果。

凡下载、安装、使用本软件，即代表本人已完整阅读、理解并自愿接受本声明全部条款。''';
}
