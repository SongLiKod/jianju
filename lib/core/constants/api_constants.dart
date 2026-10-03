/// 红果短剧官方网页源集中管理文件（硬性需求）
///
/// 数据源为 hongguoduanju.com 官方网页 SSR 数据（window._ROUTER_DATA），
/// 接口地址/参数变更时只需要修改本文件，无需改动业务代码。
class ApiConstants {
  ApiConstants._();

  // ==================== 站点 ====================
  static const String webBase = 'https://hongguoduanju.com';

  // ==================== 页面路径 ====================
  /// 首页（SSR 内含 bannerList + homeSections）
  static const String pathHome = '/';

  /// 分类页：{slug} 为分类标识，?page=N 分页
  static String pathCategory(String slug, int page) =>
      '/category/$slug?page=$page';

  /// 搜索页：路径参数为 URL 编码关键词（仅首屏 10 条，官方无分页）
  static String pathSearch(String keyword) =>
      '/search/${Uri.encodeComponent(keyword)}';

  /// 详情页
  static String pathDetail(String seriesId) => '/detail?series_id=$seriesId';

  /// 播放页（vid 省略时默认第 1 集）
  static String pathPlayer(String seriesId, String vid) =>
      '/player/$seriesId/$vid/';

  // ==================== 分类标识 ====================
  static const List<String> categorySlugs = [
    'real-drama', // 真人短剧
    'comic-drama', // 漫剧
    'ai-drama', // AI 短剧
    'comic', // 动态漫
  ];

  // ==================== 请求头 ====================
  /// 浏览器 UA（网页源要求，否则部分页面返回空壳）
  static const String browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36';

  // ==================== 分页参数 ====================
  /// 首页分类分页每页条目数（官方页面每屏约 12 条）
  static const int pageSize = 12;

  /// 官方免费可观看集数上限（accessible_episode_cnt，第4集起官方锁定）
  static const int accessibleEpisodeCount = 3;
}
