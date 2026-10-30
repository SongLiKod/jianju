import '../constants/app_constants.dart';
import '../models/drama.dart';
import '../models/episode.dart';
import 'settings_service.dart';

/// YouTube 正版嵌入源（内置目录）
///
/// 收录可在 YouTube 官方 embed 播放器中**免费播放全集**的正版视频
/// （YouTube 官方条款允许站内嵌入播放），全部集数无解锁、无付费。
///
/// 与其它源一致的分派规则（见 `ApiService`）：
/// - 剧目 ID：`yt:<slug>`（详情按前缀走 [detail]）
/// - 分集 ID：`yt:<videoId>`（取链按前缀走 [play]，直出 embed 地址）
/// - 数据源为 `youtube` 时（[enabled]），首页信息流与单源搜索走本目录；
///   跨站搜索（`searchAcross`）无论当前源是哪个都会并入本目录结果。
///
/// 视频为一次性登记的固定 videoId；若某视频被作者删除/转私有，
/// 只需在下方 [_catalog] 中替换为同名新视频的 ID 即可。
class YouTubeSource {
  YouTubeSource._();

  /// 条目/分集 ID 前缀
  static const String idPrefix = 'yt:';

  /// 展示名（设置页/来源角标共用）
  static const String sourceLabel = 'YouTube 正版源';

  static bool hasPrefix(String id) => id.startsWith(idPrefix);

  /// 当前数据源是否为 YouTube 正版源
  static bool get enabled =>
      SettingsService.dataSource == AppConstants.dataSourceYouTube;

  // ==================== 内置目录 ====================

  static const List<_YtDrama> _catalog = [
    _YtDrama(
      slug: 'shenzhu',
      title: '神竹问道之逆天崛起',
      aliases: ['竹下问道', '神竹问道'],
      abstractText:
          '少年寒冬种稻遭诬陷驱逐，凭竹筒之秘逆天改命的逆袭修仙漫剧。全季免费正版观看。',
      tags: ['玄幻', '逆袭', '修仙'],
      categoryText: 'AI漫剧',
      statusText: '完结',
      videos: [
        _YtVideo(title: '第一季 全集', videoId: 'jEc53JldqNY'),
        _YtVideo(title: '第二季 全集', videoId: 'rttXGY_WCd8'),
      ],
    ),
    _YtDrama(
      slug: 'jiutian',
      title: '九天镇压之主角就应该无敌',
      aliases: ['魔主齐天', '九天镇压', '主角就应该无敌'],
      abstractText:
          '穿越成幽冥教末代教主周穹，开局正道七大圣地举兵围山，觉醒万魔收徒系统，徒弟越强自身越强，集结万亿魔兵碾压正道。',
      tags: ['玄幻', '系统', '逆袭'],
      categoryText: 'AI漫剧',
      statusText: '连载',
      videos: [
        _YtVideo(title: '第1~3季 合集', videoId: 'xpYAB2R6Yfg'),
        _YtVideo(title: '第二季 全集', videoId: 't4rE3FlulI4'),
        _YtVideo(title: '第三季 全集', videoId: 'IaLVU5nlIGo'),
        _YtVideo(title: '第四季 全集', videoId: 'ldMJhXLLYZc'),
      ],
    ),
    _YtDrama(
      slug: 'yinyang',
      title: '我本是魔之阴阳魔帝',
      aliases: ['踏道为魔', '阴阳魔帝'],
      abstractText:
          '方凌自少年时期踏上修行之路，结识明月等伙伴，在一次次历练中坚定本心，于开阔天地间开启属于自己的传奇修行篇章。',
      tags: ['玄幻', '修仙'],
      categoryText: '动态漫',
      statusText: '连载',
      videos: [
        _YtVideo(title: '第二季 全集', videoId: 'wekf1fx3gYA'),
      ],
    ),
  ];

  // ==================== 列表 / 搜索 ====================

  /// 内置目录全部剧目（首页信息流在数据源为本源时返回它）
  static List<Drama> catalog() =>
      [for (final d in _catalog) _toDrama(d)];

  /// 目录内搜索：匹配剧名或别名（[keyword] 命中任一即返回）
  static Future<List<Drama>> search(String keyword) async {
    final kw = _norm(keyword);
    if (kw.isEmpty) return const [];
    final out = <Drama>[];
    for (final d in _catalog) {
      if (_norm(d.title).contains(kw)) {
        out.add(_toDrama(d));
        continue;
      }
      var hit = false;
      for (final a in d.aliases) {
        if (_norm(a).contains(kw) || kw.contains(_norm(a))) {
          hit = true;
          break;
        }
      }
      if (hit) out.add(_toDrama(d));
    }
    return out;
  }

  /// 首页信息流：[page] <= 0 返回全目录，翻页无更多内容
  static Future<List<Drama>> homeFeed(int page) async =>
      page <= 0 ? catalog() : const [];

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  // ==================== 详情 / 取链 ====================

  /// 详情：剧目信息 + 分集（每集为一个可嵌入的全集视频，全部 playable）
  static Future<
      ({Drama? drama, List<Episode> episodes, List<Drama> related})>
      detail(String seriesId) async {
    final slug =
        seriesId.startsWith(idPrefix) ? seriesId.substring(idPrefix.length) : '';
    final idx = _catalog.indexWhere((d) => d.slug == slug);
    if (idx < 0) {
      return (drama: null, episodes: const <Episode>[], related: const <Drama>[]);
    }
    final d = _catalog[idx];
    final episodes = <Episode>[];
    for (var i = 0; i < d.videos.length; i++) {
      episodes.add(Episode(
        itemId: '$idPrefix${d.videos[i].videoId}',
        index: i + 1,
        title: d.videos[i].title,
        playable: true, // 正版嵌入播放：全集免解锁
      ));
    }
    final related = <Drama>[];
    for (var j = 0; j < _catalog.length; j++) {
      if (j != idx) related.add(_toDrama(_catalog[j]));
    }
    return (drama: _toDrama(d), episodes: episodes, related: related);
  }

  /// 取链：直出 YouTube embed 地址（`isEmbedUrl` 为真，播放页走 WebView 分支）
  static Future<String> play(String episodeId) async {
    final vid = episodeId.startsWith(idPrefix)
        ? episodeId.substring(idPrefix.length)
        : '';
    if (!_videoIdRe.hasMatch(vid)) {
      throw Exception('无效的 YouTube 视频 ID: $episodeId');
    }
    return embedUrl(vid);
  }

  static final RegExp _videoIdRe = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// 标准 embed 地址（enablejsapi=1 供 IFrame API 控制）
  static String embedUrl(String videoId) =>
      'https://www.youtube.com/embed/$videoId'
      '?enablejsapi=1&playsinline=1&rel=0&modestbranding=1';

  /// 是否为本源的 embed 地址（播放页据此分流 WebView / mpv）
  static bool isEmbedUrl(String url) =>
      url.startsWith('https://www.youtube.com/embed/');

  /// 从 embed 地址解析 videoId（非法返回 null）
  static String? videoIdOf(String url) {
    if (!isEmbedUrl(url)) return null;
    final rest = url.substring('https://www.youtube.com/embed/'.length);
    final id = rest.split('?').first.split('/').first;
    return _videoIdRe.hasMatch(id) ? id : null;
  }

  static Drama _toDrama(_YtDrama d) => Drama(
        bookId: '$idPrefix${d.slug}',
        title: d.title,
        coverUrl: 'https://i.ytimg.com/vi/${d.videos.first.videoId}/hqdefault.jpg',
        abstractText: d.abstractText,
        tags: d.tags,
        episodeCount: d.videos.length,
        readCountText: '',
        statusText: d.statusText,
        categoryText: d.categoryText,
      );
}

/// 目录条目：一部剧（多个整季/合集视频）
class _YtDrama {
  final String slug;
  final String title;

  /// 别名（用户按别名搜索也能命中）
  final List<String> aliases;
  final String abstractText;
  final List<String> tags;
  final String categoryText;
  final String statusText;
  final List<_YtVideo> videos;

  const _YtDrama({
    required this.slug,
    required this.title,
    required this.aliases,
    required this.abstractText,
    required this.tags,
    required this.categoryText,
    required this.statusText,
    required this.videos,
  });
}

/// 目录分集：对应一个可嵌入的全集视频
class _YtVideo {
  final String title;
  final String videoId;

  const _YtVideo({required this.title, required this.videoId});
}
