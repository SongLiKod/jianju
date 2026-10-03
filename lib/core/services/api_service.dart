import 'package:flutter/foundation.dart';

import '../constants/api_constants.dart';
import '../models/drama.dart';
import '../models/episode.dart';
import '../network/http_client.dart';
import '../utils/json_utils.dart';

/// 红果短剧官方网页源业务 API：首页信息流 / 搜索 / 详情 / 播放源
///
/// 数据源为 hongguoduanju.com 官方网页 SSR 数据（window._ROUTER_DATA）。
/// 官方硬限制：每部剧仅前 [ApiConstants.accessibleEpisodeCount] 集可播。
class ApiService {
  ApiService._();

  // ==================== 首页推荐信息流 ====================

  /// 拉取首页推荐短剧。
  ///
  /// [page] 为 0 时返回首页全部分区（banner + 4 个 homeSection）合并去重结果；
  /// [page] >= 1 时按序轮询各分类页分页数据，保证持续有新内容。
  static Future<List<Drama>> fetchHomeFeed({required int page}) async {
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

  // ==================== 搜索 ====================

  /// 关键词搜索短剧。
  /// 官方网页搜索每页固定 10 条且分页参数不生效，仅返回首屏结果。
  static Future<List<Drama>> search({required String keyword}) async {
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

  // ==================== 短剧详情 ====================

  /// 详情数据：短剧信息 + 全部分集 + 详情页推荐
  static Future<({Drama? drama, List<Episode> episodes, List<Drama> related})>
      fetchDetail(String seriesId) async {
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

    // 分集：vid_list 为完整集数列表（含官方锁定集）
    final accessible =
        JsonUtils.i(detailMap, const ['accessible_episode_cnt']) ??
            ApiConstants.accessibleEpisodeCount;
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
          playable: index <= accessible,
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

  /// 获取单集直链 MP4 播放地址（官方网页播放页 video_player_info.main_url）
  static Future<String> fetchPlayUrl({
    required String seriesId,
    required String vid,
  }) async {
    final loader = await HttpClient.getSsrJson(
      ApiConstants.pathPlayer(seriesId, vid),
      loaderKeyPattern: r'player_',
    );
    final info = loader?['video_player_info'];
    if (info is Map) {
      final mainUrl = info['main_url']?.toString();
      if (mainUrl != null && mainUrl.startsWith('http')) return mainUrl;
    }
    // 兜底：递归探测直链
    final direct = JsonUtils.findFirstStringContaining(loader, '.mp4');
    if (direct != null && direct.startsWith('http')) return direct;
    throw Exception('未获取到播放地址');
  }
}
