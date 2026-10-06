import 'dart:convert';

import 'package:dio/dio.dart';

import '../constants/app_constants.dart';
import '../models/drama.dart';
import '../models/episode.dart';
import 'settings_service.dart';

/// 第三方聚合 API 数据源（52api 等，`AppConstants.api52BaseUrl`）
///
/// 仅承担 搜索 / 详情 / 播放取链；首页信息流、分类、榜单仍走官方网页源
/// （第三方聚合接口目录与榜单形态未知，先保证用户最核心的“找剧→看剧”链路）。
///
/// ID 带 `a52:` 前缀（剧目 `a52:<id>`、分集 `a52:<videoId>`），
/// 由 [ApiService] 按前缀分派，切源后旧详情页仍可用。
///
/// 接口形态以 `{code, msg, data}` 包裹；`data` 内部字段各家可能不同，
/// 这里全部做多候选容错解析，失败时抛出可读中文错误。
class Api52Source {
  Api52Source._();

  /// ID 前缀
  static const String idPrefix = 'a52:';

  /// 是否已启用（数据源 = api52 且已填 apikey）
  static bool get enabled {
    try {
      return SettingsService.dataSource == AppConstants.dataSourceApi52 &&
          SettingsService.apiKey52.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static bool hasPrefix(String id) => id.startsWith(idPrefix);

  // ==================== 页面数据 ====================

  /// 搜索（`type=search`，关键词回退链与官方源一致）
  static Future<List<Drama>> search(String keyword) async {
    String? reason;
    var responded = false;
    for (final kw in _keywords(keyword)) {
      final data = await _call('search', keyword: kw);
      if (data == null) {
        reason = '52api 无响应';
        continue;
      }
      responded = true;
      final out = <Drama>[];
      for (final m in _listOf(data)) {
        final d = _toDrama(m);
        if (d != null) out.add(d);
      }
      if (out.isNotEmpty) return out;
      reason = '无匹配结果';
    }
    if (responded) return const [];
    throw Exception(reason ?? '52api 搜索失败');
  }

  /// 详情：剧目 + 分集（推荐位第三方无对应能力，返回空）
  static Future<({Drama? drama, List<Episode> episodes, List<Drama> related})>
      detail(String bookId) async {
    final id = bookId.startsWith(idPrefix) ? bookId.substring(idPrefix.length) : bookId;
    final data = await _call('detail', id: id);
    if (data == null) {
      return (
        drama: null,
        episodes: const <Episode>[],
        related: const <Drama>[],
      );
    }
    final raw = data is Map ? data : null;
    // 详情可能整包就是条目，也可能包在 list/data 里
    Map<String, dynamic>? item;
    if (raw != null) {
      item = _firstEntry(raw);
    }
    if (item == null) {
      return (
        drama: null,
        episodes: const <Episode>[],
        related: const <Drama>[],
      );
    }
    final drama = _toDrama(item);
    final episodes = _episodesOf(data);
    return (drama: drama, episodes: episodes, related: const <Drama>[]);
  }

  /// 播放直链（`type=video`）
  static Future<String> play(String episodeId) async {
    final vid = episodeId.startsWith(idPrefix)
        ? episodeId.substring(idPrefix.length)
        : episodeId;
    final data = await _call('video', videoId: vid);
    final url = _findUrl(data);
    if (url == null) throw Exception('52api 未返回播放地址');
    return url;
  }

  // ==================== 集成 ====================

  /// 分集列表（多候选字段名）
  static List<Episode> _episodesOf(dynamic data) {
    final list = _findList(data, const [
      'episodes',
      'episode_list',
      'episodeList',
      'videos',
      'video_list',
      'list',
    ]);
    if (list == null) return const [];
    final out = <Episode>[];
    var i = 0;
    for (final e in list) {
      if (e is! Map) continue;
      i++;
      final vid = _pick(e, const ['video_id', 'vid', 'id'])?.toString() ?? '';
      final name =
          _pick(e, const ['title', 'name', 'episode_name'])?.toString() ?? '';
      if (vid.isEmpty) continue;
      out.add(Episode(
        itemId: '$idPrefix$vid',
        index: i,
        title: name.isNotEmpty ? name : '第$i集',
      ));
    }
    return out;
  }

  /// 条目 → [Drama]
  static Drama? _toDrama(Map<dynamic, dynamic> m) {
    final id = _pick(m, const ['id', 'video_id', 'series_id', 'vid'])
            ?.toString() ??
        '';
    final title =
        _pick(m, const ['title', 'name', 'video_name', 'vod_name'])
                ?.toString()
                .trim() ??
            '';
    if (id.isEmpty || title.isEmpty) return null;
    String s(List<String> keys) => _pick(m, keys)?.toString().trim() ?? '';

    return Drama(
      bookId: '$idPrefix$id',
      title: title,
      coverUrl: s(const ['cover', 'pic', 'video_cover', 'vod_pic', 'image']),
      abstractText: s(const [
        'summary',
        'desc',
        'description',
        'vod_blurb',
        'intro',
      ]),
      tags: const [],
      episodeCount:
          int.tryParse(s(const ['episode_cnt', 'episodes', 'episode', 'total'])) ??
              0,
      readCountText: s(const ['heatText', 'heat', 'hot', 'hits']),
      scoreText: s(const ['scoreText', 'score']),
      statusText: s(const ['status', 'remarks', 'vod_remarks']),
      categoryText: s(const ['category', 'type_name']),
    );
  }

  // ==================== HTTP ====================

  /// 调一次接口，返回 `data`；HTTP/业务失败抛中文错误，`code` 非成功返回 null
  static Future<dynamic> _call(
    String type, {
    String? keyword,
    String? id,
    String? videoId,
    int page = 1,
  }) async {
    final key = _apiKey();
    if (key.isEmpty) {
      throw Exception('52api：请先在设置中填写 apikey');
    }
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
      validateStatus: (code) => code != null && code < 500,
    ));
    try {
      final qp = <String, dynamic>{
        'key': key,
        'type': type,
        'page': '$page',
      };
      if (keyword != null) qp['keyword'] = keyword;
      if (id != null) qp['id'] = id;
      if (videoId != null) qp['video_id'] = videoId;
      final resp = await dio.get<dynamic>(
        AppConstants.api52BaseUrl,
        queryParameters: qp,
      );
      final status = resp.statusCode ?? 0;
      if (status != 200) throw Exception('HTTP $status');
      final body = resp.data;
      final map = body is Map
          ? body
          : body is String
              ? _tryJson(body)
              : null;
      if (map is! Map) throw Exception('响应格式未知');
      final code = _pick(map, const ['code', 'status']);
      final ok = code == null ||
          code == 0 ||
          code == 200 ||
          code == '0' ||
          code == '200' ||
          code == true;
      if (!ok) {
        final msg = _pick(map, const ['msg', 'message', 'error'])?.toString();
        throw Exception(msg == null || msg.isEmpty ? '请求失败($code)' : msg);
      }
      return map['data'] ?? map['result'] ?? map['list'] ?? map;
    } on Exception catch (e) {
      final m = e.toString();
      if (m.contains('52api：')) rethrow;
      throw Exception('52api 不可用：$m');
    }
  }

  static String _apiKey() {
    try {
      return SettingsService.apiKey52;
    } catch (_) {
      return '';
    }
  }

  static Map<String, dynamic>? _tryJson(String s) {
    try {
      final v = jsonDecode(s);
      if (v is Map) return v.cast<String, dynamic>();
    } catch (_) {
      // 非 JSON 响应
    }
    return null;
  }

  // ==================== 容错取值 ====================

  static dynamic _pick(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v != '') return v;
    }
    return null;
  }

  /// `data` 里的首个条目（条目可能直接是 map，或藏在 list/data 里）
  static Map<String, dynamic>? _firstEntry(dynamic data) {
    if (data is Map) {
      for (final key in const ['data', 'detail', 'info', 'video']) {
        final v = data[key];
        if (v is Map && v.isNotEmpty) return v.cast<String, dynamic>();
      }
      final list = _listOf(data);
      if (list.isNotEmpty) return list.first;
      if (data.isNotEmpty) return data.cast<String, dynamic>();
    }
    if (data is List && data.isNotEmpty && data.first is Map) {
      return (data.first as Map).cast<String, dynamic>();
    }
    return null;
  }

  /// `data` 里的首个数组（多候选键名）
  static List<dynamic>? _findList(dynamic data, List<String> keys) {
    if (data is List) return data;
    if (data is! Map) return null;
    for (final k in keys) {
      final v = data[k];
      if (v is List) return v;
    }
    for (final v in data.values) {
      if (v is Map) {
        final inner = _findList(v, keys);
        if (inner != null) return inner;
      }
    }
    return null;
  }

  /// 搜索/列表数组：data 本身、或常见列表键
  static List<Map<String, dynamic>> _listOf(dynamic data) {
    final raw = _findList(data, const [
      'list',
      'search_list',
      'searchList',
      'items',
      'records',
      'data',
      'videos',
    ]);
    if (raw == null) return const [];
    return [for (final e in raw) if (e is Map) e.cast<String, dynamic>()];
  }

  /// 递归找首个 http 直链（播放地址字段名各家不同）
  static String? _findUrl(dynamic v, [int depth = 0]) {
    if (depth > 4) return null;
    if (v is String) {
      final s = v.trim();
      if (s.startsWith('http') && (s.contains('.m3u8') || s.contains('.mp4'))) {
        return s;
      }
      return null;
    }
    if (v is List) {
      for (final e in v) {
        final u = _findUrl(e, depth + 1);
        if (u != null) return u;
      }
      return null;
    }
    if (v is Map) {
      for (final key in const [
        'url',
        'play_url',
        'playUrl',
        'video_url',
        'videoUrl',
        'm3u8',
        'link',
        'main_url',
        'data',
      ]) {
        final u = _findUrl(v[key], depth + 1);
        if (u != null) return u;
      }
      for (final e in v.values) {
        final u = _findUrl(e, depth + 1);
        if (u != null) return u;
      }
    }
    return null;
  }

  /// 关键词回退链（与官方源口径一致：全名 → 去季后缀 → 去标点片段 → 前缀）
  static List<String> _keywords(String title) {
    final out = <String>[];
    void add(String s) {
      final v = s.trim();
      if (v.length < 2 || out.contains(v) || out.length >= 4) return;
      out.add(v);
    }

    add(title);
    final noSuffix = title.replaceFirst(
        RegExp(r'第[0-9零一二三四五六七八九十百]+[季部期]$'), '');
    add(noSuffix);
    add(noSuffix.replaceAll(RegExp(r'''[\s!！?？,，.。:：''"“”]+'''), ''));
    final noPunct = title.replaceAll(
        RegExp(r'''[\s!！?？,，.。:：'’"“”·\-—–]+'''), '');
    add(noPunct);
    return out;
  }
}
