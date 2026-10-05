import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/api_constants.dart';
import '../models/drama.dart';
import '../models/episode.dart';
import '../network/http_client.dart';
import '../utils/json_utils.dart';
import 'api52_source.dart';
import 'maccms_source.dart';
import 'play_lines.dart';
import 'settings_service.dart';

/// 红果短剧官方网页源业务 API：首页信息流 / 搜索 / 详情 / 播放源
///
/// 数据源为 hongguoduanju.com 官方网页 SSR 数据（window._ROUTER_DATA）。
/// 官方硬限制：每部剧仅前 [ApiConstants.accessibleEpisodeCount] 集可播。
///
/// 分派规则（见 [SettingsService.dataSource]）：
/// - `line:<id>`：首页/分类/榜单/搜索/详情/播放全部走该 maccms 站点
/// - `api52`：搜索/详情/播放走第三方红果聚合源，信息流/分类/榜单仍走官方
/// - `web`：全部走官方网页源
/// - 详情/播放按 ID 前缀（`mg:`/`a52:`）分派，切源后已打开的页面仍可用
class ApiService {
  ApiService._();

  // ==================== 首页推荐信息流 ====================

  /// 拉取首页推荐短剧。
  ///
  /// [page] 为 0 时返回首页全部分区（banner + 4 个 homeSection）合并去重结果；
  /// [page] >= 1 时按序轮询各分类页分页数据，保证持续有新内容。
  static Future<List<Drama>> fetchHomeFeed({required int page}) async {
    final site = MaccmsSource.current();
    if (site != null) return site.homeFeed(page);
    if (page == 0) {
      final loader = await HttpClient.getSsrJson(ApiConstants.pathHome,
          loaderKeyPattern: r'(^|/)page$|^page$');
      final pageData = loader?['page'] ?? loader;
      final out = <Drama>[];
      final seen = <String>{};
      void addAll(dynamic list) {
        if (list is! List) return;
        for (final e in list) {
          if (e is! Map) continue;
          final d = Drama.fromJson(e);
          if (d != null && seen.add(d.bookId)) out.add(d);
        }
      }

      if (pageData is Map) {
        addAll(pageData['bannerList']);
        final sections = pageData['homeSections'];
        if (sections is List) {
          for (final s in sections) {
            if (s is Map) addAll(s['video_list']);
          }
        }
      }
      return out;
    }

    // 分页：轮询各分类页（real-drama / comic-drama / ai-drama / comic）
    final slugs = ApiConstants.categorySlugs;
    final slug = slugs[(page - 1) % slugs.length];
    final pageNum = (page - 1) ~/ slugs.length + 1;
    return fetchCategory(slug: slug, page: pageNum);
  }

  /// 分类页分页列表
  static Future<List<Drama>> fetchCategory({
    required String slug,
    required int page,
  }) async {
    final site = MaccmsSource.current();
    if (site != null) return site.category(slug, page);
    for (var attempt = 0; attempt < 3; attempt++) {
      final loader = await HttpClient.getSsrJson(
        ApiConstants.pathCategory(slug, page),
        loaderKeyPattern: r'category_',
      );
      final list = loader?['recommendList'];
      if (list is List) {
        return list
            .whereType<Map>()
            .map(Drama.fromJson)
            .whereType<Drama>()
            .toList();
      }
      debugPrint('分类载荷缺失，重试 ${attempt + 1}/3: $slug page=$page');
      await Future<void>.delayed(Duration(milliseconds: 400 * (1 << attempt)));
    }
    return const [];
  }

  // ==================== 排行榜 ====================

  /// 榜单列表（榜单标识见 [ApiConstants.rankSlugs]）。
  ///
  /// 返回榜单更新说明、条目与总页数（每页 20 条，见 content.pagination）。
  ///
  /// 官网榜单页的 SSR 载荷有时缺 content（同一 URL 重取即可拿到，约五成命中），
  /// 这里最多重试 5 次，仍缺失才抛错。
  static Future<({String updatedText, List<Drama> items, int totalPages})>
      fetchRank({required String slug, int page = 1}) async {
    final site = MaccmsSource.current();
    if (site != null) return site.rank(slug, page);
    for (var attempt = 0; attempt < 5; attempt++) {
      final loader = await HttpClient.getSsrJson(
        ApiConstants.pathRank(slug, page),
        loaderKeyPattern: r'rank_',
      );
      final updatedText = loader?['updatedText']?.toString() ?? '';
      final content = loader?['content'];
      if (content is Map && content['rankList'] is List) {
        final items = <Drama>[];
        for (final e in content['rankList'] as List) {
          if (e is! Map) continue;
          final d = Drama.fromJson(e);
          if (d != null) items.add(d);
        }
        final pagination = content['pagination'];
        final totalPages = pagination is Map
            ? JsonUtils.i(pagination, const ['totalPages']) ?? 1
            : 1;
        return (updatedText: updatedText, items: items, totalPages: totalPages);
      }
      debugPrint('榜单载荷缺失，重试 ${attempt + 1}/5: $slug page=$page');
      await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
    throw Exception('榜单数据缺失: $slug page=$page');
  }

  // ==================== 分类/榜单 tab ====================

  /// 分类页 tab：`slug -> 中文名`（站点模式取该站 `class` 全站分类）
  static Future<Map<String, String>> fetchCategoryLabels() async {
    final site = MaccmsSource.current();
    if (site == null) return ApiConstants.categoryLabels;
    return site.categoryTabs();
  }

  /// 排行榜 tab：`slug -> 中文名`（站点模式为 `hot:<type_id>` 按热度倒序）
  static Future<Map<String, String>> fetchRankLabels() async {
    final site = MaccmsSource.current();
    if (site == null) return ApiConstants.rankLabels;
    final tabs = await site.categoryTabs();
    final out = <String, String>{};
    // 榜单条为横向滚动，最多放 8 个（与分类 tab 上限一致）
    for (final e in tabs.entries) {
      if (out.length >= 8) break;
      out['hot:${e.key}'] = '${e.value}榜';
    }
    if (out.isEmpty) out['hot:5'] = '短剧榜';
    return out;
  }

  // ==================== 搜索 ====================

  /// 关键词搜索短剧（只查当前数据源，见 [searchAcross] 的跨站版本）。
  /// 官方网页搜索每页固定 10 条且分页参数不生效，仅返回首屏结果。
  static Future<List<Drama>> search({required String keyword}) async {
    final site = MaccmsSource.current();
    if (site != null) return site.search(keyword);
    if (Api52Source.enabled) return Api52Source.search(keyword);
    return _searchOfficial(keyword);
  }

  /// 官方网页源搜索（首屏 10 条）
  static Future<List<Drama>> _searchOfficial(String keyword) async {
    final loader = await HttpClient.getSsrJson(
      ApiConstants.pathSearch(keyword),
      loaderKeyPattern: r'search_',
    );
    final list = loader?['searchList'];
    if (list is! List) return const [];
    final out = <Drama>[];
    for (final e in list) {
      if (e is! Map) continue;
      final videoData = e['video_data'];
      final source = videoData is Map ? videoData : e;
      final d = Drama.fromJson(source);
      if (d != null) out.add(d);
    }
    return out;
  }

  /// 单站查询并发上限（站点多时避免同时打满全部源）
  static const int _searchConcurrency = 8;

  /// 单站查询超时：超时站点直接跳过，不拖累整体
  static const Duration _searchPerSource = Duration(seconds: 10);

  /// 整次跨站搜索总预算：到点即用已合并结果收尾
  static const Duration _searchBudget = Duration(seconds: 20);

  /// 跨站聚合搜索：当前数据源 + 官方网页源 + 52api（启用时）+ 全部 API 整站站点
  ///
  /// 各站并发查询，站点陆续返回时通过 [onUpdate] 吐出已合并结果
  /// （参数为 合并结果 / 已完成站数 / 总站数），界面可边搜边展示；
  /// 单站失败或超时只跳过该站。合并规则见 [mergeSearchResults]。
  static Future<List<Drama>> searchAcross({
    required String keyword,
    required int limit,
    void Function(List<Drama> merged, int done, int total)? onUpdate,
  }) async {
    final sources = _searchSources(keyword);
    final total = sources.length;
    final results = <int, List<Drama>>{};
    var done = 0;
    var closed = false;

    void emit() {
      onUpdate?.call(mergeSearchResults(results, limit), done, total);
    }

    var next = 0;
    Future<void> runWorker() async {
      while (true) {
        if (closed) return;
        final i = next++;
        if (i >= sources.length) return;
        final src = sources[i];
        try {
          final items = await src.run().timeout(_searchPerSource);
          if (closed) return;
          results[src.pri] = items;
        } catch (_) {
          // 单站无响应/超时/无结果：跳过，其余站点继续
        }
        if (closed) return;
        done++;
        emit();
      }
    }

    try {
      await Future.wait(
              List.generate(_searchConcurrency, (_) => runWorker()))
          .timeout(_searchBudget);
    } on TimeoutException {
      // 总预算耗尽：按已到手的结果收尾
    }
    closed = true;
    emit();
    return mergeSearchResults(results, limit);
  }

  /// 跨站搜索的查询目标与优先级（当前源最前，其次官方、52api，
  /// 其余整站站点按历史测速排序）
  static List<({int pri, Future<List<Drama>> Function() run})>
      _searchSources(String keyword) {
    final out = <({int pri, Future<List<Drama>> Function() run})>[];
    var pri = 0;
    final current = MaccmsSource.current();
    if (current != null) {
      final site = current;
      out.add((pri: pri++, run: () => site.search(keyword)));
    }
    out.add((pri: pri++, run: () => _searchOfficial(keyword)));
    if (Api52Source.enabled) {
      out.add((pri: pri++, run: () => Api52Source.search(keyword)));
    }
    pri = 10;
    final seen = {if (current != null) current.line.id};
    for (final line in PlayLineResolver.orderedLines()) {
      if (line.mode != PlayLineMode.api || seen.contains(line.id)) continue;
      seen.add(line.id);
      final site = MaccmsSource(line);
      out.add((pri: pri++, run: () => site.search(keyword)));
    }
    return out;
  }

  /// 跨站结果合并：按来源优先级升序拼接，归一化剧名去重，截断到 [limit]
  static List<Drama> mergeSearchResults(
      Map<int, List<Drama>> byPriority, int limit) {
    final keys = byPriority.keys.toList()..sort();
    final out = <Drama>[];
    final seen = <String>{};
    for (final k in keys) {
      for (final d in byPriority[k]!) {
        final t = PlayLineResolver.normalizeTitle(d.title);
        final key = t.isEmpty ? d.bookId : t;
        if (!seen.add(key)) continue;
        out.add(d);
        if (limit > 0 && out.length >= limit) return out;
      }
    }
    return out;
  }

  // ==================== 短剧详情 ====================

  /// 详情数据：短剧信息 + 全部分集 + 详情页推荐
  static Future<({Drama? drama, List<Episode> episodes, List<Drama> related})>
      fetchDetail(String seriesId) async {
    // 前缀分派：整站源/聚合源的条目用自带 ID 还原，不依赖当前数据源选择
    if (MaccmsSource.hasPrefix(seriesId)) {
      final site = MaccmsSource.byId(seriesId);
      if (site == null) throw Exception('站点线路已变更，请返回后重试');
      return site.detail(seriesId);
    }
    if (Api52Source.hasPrefix(seriesId)) {
      return Api52Source.detail(seriesId);
    }
    final loader = await HttpClient.getSsrJson(
      ApiConstants.pathDetail(seriesId),
      loaderKeyPattern: r'detail',
    );
    final page = loader?['detail_page'] ?? loader;
    if (page is! Map) {
      return (drama: null, episodes: const <Episode>[], related: const <Drama>[]);
    }
    final detail = page['seriesDetail'];
    final detailMap = detail is Map ? detail : page;

    final drama = Drama.fromJson(detailMap) ??
        Drama.fromJson({...detailMap, 'series_id': seriesId});

    // 分集：vid_list 为完整集数列表
    // playable 恒为 true：前 3 集走官方直链，后续集数由全集源兜底（见 fetchPlayUrl）
    final vidList = detailMap['vid_list'];
    final episodes = <Episode>[];
    if (vidList is List) {
      var index = 1;
      for (final v in vidList) {
        final vid = v is Map ? JsonUtils.s(v, const ['vid', 'v_id']) : v?.toString();
        if (vid == null || vid.isEmpty) continue;
        episodes.add(Episode(
          itemId: vid,
          index: index,
          title: '第$index集',
        ));
        index++;
      }
    }

    // 相关推荐：可能是列表，也可能是 {videoList: [...]} 的延后注入载荷
    final rec = page['recommendations'];
    final recList = rec is List
        ? rec
        : rec is Map
            ? (rec['videoList'] ?? rec['list'] ?? rec['recommendList'])
            : null;
    final related = <Drama>[];
    if (recList is List) {
      for (final e in recList) {
        if (e is! Map) continue;
        final d = Drama.fromJson(e);
        if (d != null) related.add(d);
      }
    }
    return (drama: drama, episodes: episodes, related: related);
  }

  // ==================== 播放源 ====================

  /// 获取单集播放地址。
  ///
  /// 1. 手动锁定线路（见 [SettingsService.pinnedLineId]）→ 只走该线路；
  /// 2. 默认 → 官方网页直链 MP4（前 [ApiConstants.accessibleEpisodeCount] 集可用）；
  /// 3. 官方无直链 → 内置线路按测速分批竞速，取最快成功者（见 [PlayLineResolver]）。
  ///
  /// [excludeUrl] 为已确认打不开的地址：各来源返回同一地址时一律跳过，
  /// 转而走下一级来源（官方 → 线路竞速），用于播放失败后的自动换源重试。
  static Future<String> fetchPlayUrl({
    required String seriesId,
    required String vid,
    String? title,
    int? episodeIndex,
    String? excludeUrl,
  }) async {
    // 整站源分集：按 ID 内嵌的源组/集序号取该站精确直链
    if (MaccmsSource.hasPrefix(vid)) {
      final site = MaccmsSource.byId(vid);
      if (site != null) {
        try {
          final url = await site.playUrl(vid);
          if (url == excludeUrl) throw Exception('该地址已失效');
          return url;
        } catch (e) {
          debugPrint('站点取链失败，转线路竞速: $e');
          if (title != null && episodeIndex != null) {
            return PlayLineResolver.resolve(
              title: title,
              episodeIndex: episodeIndex,
              exclude: excludeUrl,
            );
          }
          rethrow;
        }
      }
    }
    // 第三方红果聚合源分集
    if (Api52Source.hasPrefix(vid)) {
      final url = await Api52Source.play(vid);
      if (url != excludeUrl) return url;
      debugPrint('聚合源直链已失效，转官方/线路兜底');
      // 不返回：继续走下方 官方直链 → 线路竞速 的兜底顺序
    }

    final pinned = _pinnedLineId();

    // 手动锁定：跳过官方源，严格按所选线路解析
    if (pinned.isNotEmpty && title != null && episodeIndex != null) {
      return PlayLineResolver.resolve(
        title: title,
        episodeIndex: episodeIndex,
        exclude: excludeUrl,
      );
    }

    try {
      final loader = await HttpClient.getSsrJson(
        ApiConstants.pathPlayer(seriesId, vid),
        loaderKeyPattern: r'player_',
      );
      final info = loader?['video_player_info'];
      if (info is Map) {
        final mainUrl = info['main_url']?.toString();
        if (mainUrl != null &&
            mainUrl.startsWith('http') &&
            mainUrl != excludeUrl) {
          return mainUrl;
        }
      }
      // 兜底：递归探测直链
      final direct = JsonUtils.findFirstStringContaining(loader, '.mp4');
      if (direct != null && direct.startsWith('http') && direct != excludeUrl) {
        return direct;
      }
      throw Exception(excludeUrl != null ? '官方直链已失效' : '官方播放页无直链');
    } catch (e) {
      debugPrint('官方播放页取链失败，转内置线路: $e');
    }

    if (title != null && episodeIndex != null) {
      return PlayLineResolver.resolve(
        title: title,
        episodeIndex: episodeIndex,
        exclude: excludeUrl,
      );
    }
    throw Exception('未获取到播放地址');
  }

  static String _pinnedLineId() {
    try {
      return SettingsService.pinnedLineId;
    } catch (_) {
      return '';
    }
  }
}
