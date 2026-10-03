import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/api_constants.dart';
import '../models/drama.dart';
import '../models/episode.dart';
import 'play_lines.dart';
import 'settings_service.dart';

/// maccms 站点整站数据源（标准 `provide/vod` 接口）
///
/// 首页信息流 / 分类 / 排行榜 / 搜索 / 详情 / 播放直链全部走当前站点，
/// 站点由设置里的数据源 `line:<线路id>` 决定（仅 API 模式线路可作整站源）。
///
/// 条目与分集的自增 ID 均带 `mg:` 前缀并内嵌线路 id：
/// - 剧目：`mg:<lineId>:<vodId>`
/// - 分集：`mg:<lineId>:<vodId>:<源组下标>:<集序号>`
/// 前缀分派（见 [MaccmsSource.byId]）保证切源后已打开的详情/播放页仍可用。
class MaccmsSource {
  MaccmsSource(this.line);

  final PlayLine line;

  /// ID 前缀
  static const String idPrefix = 'mg:';

  /// 分类/榜单 tab 的偏好顺序（maccms 全站分类杂而多，按短剧相关性截取）
  static const List<String> tabPreference = [
    '短剧',
    'AI漫剧',
    '擦边短剧',
    '真人短剧',
    '漫剧',
    'AI短剧',
    '电视剧',
    '电影',
    '动漫',
    '综艺',
    '纪录片',
  ];

  /// 最多展示的分类/榜单 tab 数
  static const int maxTabs = 8;

  /// 候选分类内容探测上限（并行轻量请求，用于过滤无内容分类）
  static const int probeLimit = 16;

  /// class（全站分类）按线路缓存，避免每次翻页都拉
  static final Map<String, Map<String, String>> _tabsCache = {};

  // ==================== 数据源分派 ====================

  /// 当前设置为整站站点源时返回实例，否则 null
  static MaccmsSource? current() {
    try {
      final ds = SettingsService.dataSource;
      if (!ds.startsWith('line:')) return null;
      return fromLineId(ds.substring(5));
    } catch (_) {
      return null;
    }
  }

  /// 按线路 id 构建（非 API 模式线路不作整站源）
  static MaccmsSource? fromLineId(String lineId) {
    if (lineId.isEmpty) return null;
    final line = PlayLineResolver.byId(lineId);
    if (line == null || line.mode != PlayLineMode.api) return null;
    return MaccmsSource(line);
  }

  /// [id] 是否为整站源 ID（剧目/分集通用）
  static bool hasPrefix(String id) => id.startsWith(idPrefix);

  /// 从剧目/分集 ID 还原数据源实例（切源后旧详情页仍可解析）
  static MaccmsSource? byId(String id) {
    if (!hasPrefix(id)) return null;
    final parts = id.split(':');
    if (parts.length < 3) return null;
    return fromLineId(parts[1]);
  }

  // ==================== 页面数据 ====================

  /// 首页信息流：首屏取主分类第 1 页，后续页顺延翻页
  Future<List<Drama>> homeFeed(int page) async {
    final tabs = await categoryTabs();
    final tid = tabs.isEmpty ? null : tabs.keys.first;
    final res = await _detail(t: tid, page: page + 1);
    if (res == null) throw Exception('${line.name} 接口无响应');
    return _toDramas(res.items);
  }

  /// 分类分页（[slug] 为 type_id）
  Future<List<Drama>> category(String slug, int page) async {
    final res = await _detail(t: slug, page: page);
    if (res == null) throw Exception('${line.name} 接口无响应');
    return _toDramas(res.items);
  }

  /// 榜单（[slug] 形如 `hot:<type_id>`，按 hits 倒序）
  Future<({String updatedText, List<Drama> items, int totalPages})> rank(
      String slug, int page) async {
    final tabs = await categoryTabs();
    final fallbackTid = tabs.isEmpty ? null : tabs.keys.first;
    final tid = slug.startsWith('hot:') ? slug.substring(4) : fallbackTid;
    final res = await _detail(t: tid, by: 'hits', page: page);
    if (res == null) throw Exception('${line.name} 接口无响应');
    final total =
        res.pagecount < 1 ? 1 : (res.pagecount > 200 ? 200 : res.pagecount);
    return (
      updatedText: '按热度排序 · 共$total页',
      items: _toDramas(res.items),
      totalPages: total,
    );
  }

  /// 搜索：关键词回退链（裸 LIKE，含空格/标点的站名整串必失败）+
  /// 剧名匹配过滤，完全同名者优先
  Future<List<Drama>> search(String keyword) async {
    String? reason;
    var responded = false;
    for (final kw in PlayLineResolver.searchKeywords(keyword)) {
      final res = await _detail(wd: kw);
      if (res == null) {
        reason = '接口无响应';
        continue;
      }
      responded = true;
      final hits = <Drama>[];
      for (final m in res.items) {
        final name = m['vod_name']?.toString() ?? '';
        if (!PlayLineResolver.nameMatches(name, keyword)) continue;
        final d = toDrama(m, line.id);
        if (d != null) hits.add(d);
      }
      if (hits.isNotEmpty) {
        final t = PlayLineResolver.normalizeTitle(keyword);
        final indexed = hits.asMap().entries.toList();
        indexed.sort((a, b) {
          final ae = PlayLineResolver.normalizeTitle(a.value.title) == t ? 0 : 1;
          final be = PlayLineResolver.normalizeTitle(b.value.title) == t ? 0 : 1;
          if (ae != be) return ae - be;
          return a.key.compareTo(b.key);
        });
        return indexed.map((e) => e.value).toList();
      }
      reason = '无匹配结果';
    }
    if (responded) return const [];
    throw Exception(reason ?? '搜索无结果');
  }

  /// 详情：剧目 + 全部分集（首组播放源）+ 同分类推荐
  Future<({Drama? drama, List<Episode> episodes, List<Drama> related})>
      detail(String bookId) async {
    final vodId = _vodIdOf(bookId);
    if (vodId == null) {
      return (
        drama: null,
        episodes: const <Episode>[],
        related: const <Drama>[],
      );
    }
    final res = await _detail(ids: vodId);
    final m = res == null || res.items.isEmpty ? null : res.items.first;
    if (m == null) {
      return (
        drama: null,
        episodes: const <Episode>[],
        related: const <Drama>[],
      );
    }
    final episodes = episodesOf(m, line.id);
    final drama = toDrama(m, line.id);
    final related = await _related(m);
    return (drama: drama, episodes: episodes, related: related);
  }

  /// 播放直链：按分集 ID 里的源组/集序号在 `vod_play_url` 中取精确地址，
  /// 源组内取不到时回退首组同集
  Future<String> playUrl(String episodeId) async {
    final parts = episodeId.split(':');
    if (parts.length < 5 || parts[0] != 'mg') {
      throw Exception('播放标识无效');
    }
    final vodId = parts[2];
    final sid = int.tryParse(parts[3]) ?? 0;
    final nid = int.tryParse(parts[4]) ?? 1;

    final res = await _detail(ids: vodId);
    final m = res == null || res.items.isEmpty ? null : res.items.first;
    if (m == null) throw Exception('${line.name} 无此剧');

    final groups = (m['vod_play_url']?.toString() ?? '').split(r'$$$');
    if (groups.isEmpty || groups.first.isEmpty) {
      throw Exception('该站无播放资源');
    }
    final primary =
        sid >= 0 && sid < groups.length ? groups[sid] : groups.first;
    final candidates = <String>[
      primary,
      if (primary != groups.first) groups.first,
    ];
    for (final g in candidates) {
      final url = urlOfEpisode(g, nid);
      if (url != null) return url;
    }
    throw Exception('该集无播放地址');
  }

  // ==================== 分类 tab ====================

  /// 分类 tab：`type_id -> type_name`（按 [tabPreference] 排序，
  /// 过滤无内容分类，最多 [maxTabs] 条）
  Future<Map<String, String>> categoryTabs() async {
    final cached = _tabsCache[line.id];
    if (cached != null) return cached;

    final json = await _getJson('ac=list&pg=1');
    final classes = json?['class'];
    final byName = <String, String>{};
    if (classes is List) {
      for (final c in classes) {
        if (c is! Map) continue;
        final id = c['type_id']?.toString() ?? '';
        final name = c['type_name']?.toString() ?? '';
        if (id.isEmpty || name.isEmpty) continue;
        byName[id] = name;
      }
    }
    if (byName.isEmpty) {
      // class 拉取失败：返回兜底但不缓存，下次进入页面重试
      return const {'5': '短剧', '41': 'AI漫剧', '2': '电视剧', '1': '电影'};
    }

    final ordered = <String, String>{};
    for (final want in tabPreference) {
      byName.forEach((id, name) {
        if (name == want) ordered[id] = name;
      });
    }
    byName.forEach((id, name) => ordered.putIfAbsent(id, () => name));

    // 候选最多探测 [probeLimit] 条，剔除没有内容的分类
    final candidates = <String, String>{};
    for (final e in ordered.entries) {
      if (candidates.length >= probeLimit) break;
      candidates[e.key] = e.value;
    }
    final visible = await _dropEmptyTypes(candidates);
    if (visible.length > maxTabs) {
      final keep = <String, String>{};
      for (final e in visible.entries) {
        if (keep.length >= maxTabs) break;
        keep[e.key] = e.value;
      }
      return _cacheTabs(keep);
    }
    return _cacheTabs(visible);
  }

  /// 并行探测候选分类的内容数，剔除 `total=0` 的空分类
  /// （探测失败的分类保留；全部失败原样返回，避免误隐藏）
  Future<Map<String, String>> _dropEmptyTypes(Map<String, String> tabs) async {
    if (tabs.length <= 1) return tabs;
    var responded = 0;
    final counts = await Future.wait(tabs.keys.map((id) async {
      final j = await _getJson('ac=list&t=$id&pg=1');
      if (j == null) return null;
      responded++;
      final total = int.tryParse(j['total']?.toString() ?? '');
      if (total != null) return total;
      final list = j['list'];
      return list is List ? list.length : -1;
    }));
    if (responded == 0) return tabs;
    final visible = <String, String>{};
    var i = 0;
    for (final e in tabs.entries) {
      final n = counts[i++];
      if (n == null || n < 0 || n > 0) visible[e.key] = e.value;
    }
    return visible.isEmpty ? tabs : visible;
  }

  Map<String, String> _cacheTabs(Map<String, String> tabs) {
    if (tabs.isEmpty) return tabs;
    if (_tabsCache.length >= 8) _tabsCache.clear();
    _tabsCache[line.id] = tabs;
    return tabs;
  }

  // ==================== 条目/分集映射 ====================

  /// maccms 条目 → [Drama]（vod_id/vod_name 缺失返回 null）
  static Drama? toDrama(Map<dynamic, dynamic> m, String lineId) {
    final vodId = m['vod_id']?.toString() ?? '';
    final title = m['vod_name']?.toString().trim() ?? '';
    if (vodId.isEmpty || title.isEmpty) return null;

    String s(String k) => m[k]?.toString().trim() ?? '';
    var cover = s('vod_pic');
    if (cover.isEmpty) cover = s('vod_pic_thumb');

    final tags = <String>[];
    final area = s('vod_area');
    if (area.isNotEmpty) tags.add(area);
    final year = s('vod_year');
    if (year.isNotEmpty) tags.add(year);

    final remarks = s('vod_remarks');
    final score = double.tryParse(s('vod_score')) ?? 0;

    return Drama(
      bookId: '$idPrefix$lineId:$vodId',
      title: title,
      coverUrl: cover,
      abstractText:
          _stripHtml(s('vod_blurb').isNotEmpty ? s('vod_blurb') : s('vod_content')),
      tags: tags,
      episodeCount: _episodeCount(m),
      readCountText: _heatText(s('vod_hits')),
      scoreText: score > 0 ? '评分${score.toStringAsFixed(1)}' : '',
      statusText: remarks,
      categoryText: s('type_name'),
    );
  }

  /// 播放条目 → 分集列表（取首组播放源，[Episode.itemId] 内嵌源组/集序号）
  static List<Episode> episodesOf(Map<dynamic, dynamic> m, String lineId) {
    final vodId = m['vod_id']?.toString() ?? '';
    final play = m['vod_play_url']?.toString() ?? '';
    if (vodId.isEmpty || play.isEmpty) return const [];
    final first = play.split(r'$$$').first;
    if (first.isEmpty) return const [];

    final out = <Episode>[];
    var i = 0;
    for (final raw in first.split('#')) {
      i++;
      final entry = _unescape(raw.trim());
      var name = '';
      if (!entry.startsWith('http')) {
        final dollar = entry.indexOf(r'$');
        if (dollar > 0) name = entry.substring(0, dollar).trim();
      }
      out.add(Episode(
        itemId: '$idPrefix$lineId:$vodId:0:$i',
        index: i,
        title: name.isNotEmpty ? name : '第$i集',
      ));
    }
    return out;
  }

  static int _episodeCount(Map<dynamic, dynamic> m) {
    final play = m['vod_play_url']?.toString() ?? '';
    final first = play.split(r'$$$').first;
    if (first.isNotEmpty) {
      final n = first.split('#').length;
      if (n > 0) return n;
    }
    return int.tryParse(m['vod_serial']?.toString() ?? '') ?? 0;
  }

  static String? _vodIdOf(String id) {
    if (!hasPrefix(id)) return null;
    final parts = id.split(':');
    if (parts.length < 3 || parts[2].isEmpty) return null;
    return parts[2];
  }

  /// `组内播放串` + 集序号 → 直链（组内 `集名$url` 以 `#` 分隔）
  static String? urlOfEpisode(String group, int nid) {
    final eps = group.split('#');
    if (nid < 1 || nid > eps.length) return null;
    final entry = _unescape(eps[nid - 1].trim());
    if (entry.startsWith('http')) return entry;
    final dollar = entry.indexOf(r'$');
    if (dollar < 0) return null;
    final url = entry.substring(dollar + 1).trim();
    return url.startsWith('http') ? url : null;
  }

  static String _heatText(String raw) {
    final n = int.tryParse(raw.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    if (n <= 0) return '';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万热度';
    return '$n热度';
  }

  static String _stripHtml(String s) {
    if (s.isEmpty) return '';
    final noTags = s.replaceAll(RegExp(r'<[^>]*>'), ' ');
    return noTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _unescape(String s) =>
      s.replaceAll(r'\/', '/').replaceAll(r'\u002F', '/').replaceAll(r'\u002f', '/');

  List<Drama> _toDramas(List<Map<String, dynamic>> items) {
    final out = <Drama>[];
    final seen = <String>{};
    for (final m in items) {
      final d = toDrama(m, line.id);
      if (d != null && seen.add(d.bookId)) out.add(d);
    }
    return out;
  }

  // ==================== 推荐 ====================

  Future<List<Drama>> _related(Map<dynamic, dynamic> m) async {
    final typeId = m['type_id']?.toString() ?? '';
    final vodId = m['vod_id']?.toString() ?? '';
    if (typeId.isEmpty) return const [];
    final seed = int.tryParse(vodId) ?? 0;
    final res = await _detail(t: typeId, page: 2 + seed % 4);
    if (res == null) return const [];
    final out = <Drama>[];
    for (final item in res.items) {
      if (item['vod_id']?.toString() == vodId) continue;
      final d = toDrama(item, line.id);
      if (d != null) out.add(d);
      if (out.length >= 10) break;
    }
    return out;
  }

  // ==================== HTTP ====================

  /// `ac=detail` 查询：返回条目与总页数；网络/响应异常返回 null
  Future<({List<Map<String, dynamic>> items, int pagecount})?> _detail({
    String? t,
    String? wd,
    String? ids,
    String? by,
    int page = 1,
  }) async {
    final parts = <String>['ac=detail'];
    if (t != null && t.isNotEmpty) parts.add('t=$t');
    if (wd != null && wd.isNotEmpty) {
      parts.add('wd=${Uri.encodeComponent(wd)}');
    }
    if (ids != null && ids.isNotEmpty) parts.add('ids=$ids');
    if (by != null && by.isNotEmpty) parts.add('by=$by');
    parts.add('pg=$page');
    final json = await _getJson(parts.join('&'));
    if (json == null) return null;
    final list = json['list'];
    final items = list is List
        ? list.whereType<Map>().toList()
        : const <Map<dynamic, dynamic>>[];
    final pagecount = int.tryParse(json['pagecount']?.toString() ?? '') ?? 0;
    return (
      items: [
        for (final e in items) e.cast<String, dynamic>(),
      ],
      pagecount: pagecount,
    );
  }

  Future<Map<String, dynamic>?> _getJson(String query) async {
    try {
      final resp = await _dio.get<dynamic>(
        '${line.base}/api.php/provide/vod/?$query',
      );
      final body = resp.data?.toString() ?? '';
      if (body.isEmpty) {
        debugPrint('[整站] ${line.name} 空响应: $query '
            'HTTP ${resp.statusCode} headers=${resp.headers.map['content-type']}');
        return null;
      }
      final v = jsonDecode(body);
      if (v is! Map) {
        debugPrint('[整站] ${line.name} 非对象响应: $query -> ${v.runtimeType}');
        return null;
      }
      return v.cast<String, dynamic>();
    } on DioException catch (e) {
      debugPrint(
          '[整站] ${line.name} 请求失败: $query -> HTTP ${e.response?.statusCode} ${e.type.name} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[整站] ${line.name} 响应解析失败: $query -> $e');
      return null;
    }
  }

  late final Dio _dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (code) => code != null && code < 500,
        headers: {
          'user-agent': ApiConstants.browserUserAgent,
          'accept': 'application/json,text/plain,*/*',
          'accept-language': 'zh-CN,zh;q=0.9',
          'referer': '${line.base}/',
        },
      ));
}
