import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/api_constants.dart';
import '../constants/app_constants.dart';
import 'settings_service.dart';
import 'storage_service.dart';

/// 播放线路适配模式
enum PlayLineMode {
  /// maccms 提供器 API：`/api.php/provide/vod/?ac=detail&wd=` 返回 JSON
  api,

  /// maccms 网页链路：搜索页 → 详情页 → 播放页（`player_aaaa` JSON 取链）
  html,
}

/// 单条内置播放线路（第三方公开短剧站，仅只读解析）
class PlayLine {
  final String id;
  final String name;
  final String base;
  final PlayLineMode mode;

  const PlayLine({
    required this.id,
    required this.name,
    required this.base,
    required this.mode,
  });
}

/// 内置线路注册表（20 条，均以《宴律》第 40 集端到端验证可解析 m3u8）
const List<PlayLine> kPlayLines = [
  // ---- 提供器 API 模式 ----
  PlayLine(id: 'bsvod.com', name: 'bsvod.com', base: 'https://bsvod.com', mode: PlayLineMode.api),
  PlayLine(id: 'bhvod.com', name: 'bhvod.com', base: 'https://bhvod.com', mode: PlayLineMode.api),
  PlayLine(id: 'danbotv.com', name: 'danbotv.com', base: 'https://danbotv.com', mode: PlayLineMode.api),
  PlayLine(id: 'heimao.us', name: 'heimao.us', base: 'https://heimao.us', mode: PlayLineMode.api),
  PlayLine(id: 'heimaovod.com', name: 'heimaovod.com', base: 'https://heimaovod.com', mode: PlayLineMode.api),
  PlayLine(id: 'imxvod.com', name: 'imxvod.com', base: 'https://imxvod.com', mode: PlayLineMode.api),
  PlayLine(id: 'lvvod.com', name: 'lvvod.com', base: 'https://lvvod.com', mode: PlayLineMode.api),
  PlayLine(id: 'mxvod.us', name: 'mxvod.us', base: 'https://mxvod.us', mode: PlayLineMode.api),
  PlayLine(id: 'gmmov.com', name: 'gmmov.com', base: 'https://gmmov.com', mode: PlayLineMode.api),
  PlayLine(id: 'iuzvod.com', name: 'iuzvod.com', base: 'https://iuzvod.com', mode: PlayLineMode.api),
  PlayLine(id: 'zmvod.com', name: 'zmvod.com', base: 'https://zmvod.com', mode: PlayLineMode.api),
  // ---- 网页链路模式 ----
  PlayLine(id: 'thjzsj.cn', name: 'thjzsj.cn', base: 'https://thjzsj.cn', mode: PlayLineMode.html),
  PlayLine(id: 'bcvod.top', name: 'bcvod.top', base: 'https://bcvod.top', mode: PlayLineMode.html),
  PlayLine(id: 'bgmov.com', name: 'bgmov.com', base: 'https://bgmov.com', mode: PlayLineMode.html),
  PlayLine(id: 'chvod.com', name: 'chvod.com', base: 'https://chvod.com', mode: PlayLineMode.html),
  PlayLine(id: 'jjmov.com', name: 'jjmov.com', base: 'https://jjmov.com', mode: PlayLineMode.html),
  PlayLine(id: 'bcvod.me', name: 'bcvod.me', base: 'https://bcvod.me', mode: PlayLineMode.html),
  PlayLine(id: 'bcvod.us', name: 'bcvod.us', base: 'https://bcvod.us', mode: PlayLineMode.html),
  PlayLine(id: 'chmov.com', name: 'chmov.com', base: 'https://chmov.com', mode: PlayLineMode.html),
  PlayLine(id: 'bcvod.one', name: 'bcvod.one', base: 'https://bcvod.one', mode: PlayLineMode.html),
];

/// 单条线路的测速统计（EMA 平均耗时 + 成功/连续失败次数）
class PlayLineStat {
  /// 平均解析耗时（毫秒），null 表示尚无成功样本
  final double? emaMs;

  /// 累计成功次数
  final int ok;

  /// 连续失败次数（成功即清零）
  final int fails;

  const PlayLineStat({this.emaMs, this.ok = 0, this.fails = 0});
}

class _Win {
  final PlayLine line;
  final String url;
  const _Win(this.line, this.url);
}

/// 线路解析器：多线路竞速 + 测速排序 + 手动锁定
///
/// - 无手动线路时按历史测速把线路排序，分批并发竞速，首个成功即为“最快线路”
/// - 用户在播放器里锁定某条线路后，[resolve] 只走该线路
/// - 解析结果按（线路, 标题, 集号）做会话内缓存
class PlayLineResolver {
  PlayLineResolver._();

  /// 单条线路解析总超时
  static const Duration _lineTimeout = Duration(seconds: 30);

  /// 竞速并发批量
  static const int _batchSize = 5;

  /// 搜索结果最多尝试的候选详情数
  static const int _maxCandidates = 3;

  /// 单次解析最多尝试的搜索关键词数
  static const int _maxKeywords = 4;

  /// 缓存上限（超出后整体清空，避免无界增长）
  static const int _maxCache = 200;

  /// 未测速线路的默认分值（毫秒）
  static const double _unknownScore = 6000;

  /// 连续失败一次的惩罚分（毫秒）
  static const double _failPenalty = 1500;

  /// 当前播放所用线路（供 UI 高亮）
  static PlayLine? lastUsedLine;

  /// 最近一次失败原因（中文，供播放页展示）
  static String? lastError;

  static final Map<String, String> _cache = {};
  static Map<String, dynamic>? _statsCache;

  /// 测试辅助：清空缓存与状态
  static void clearCaches() {
    _cache.clear();
    _statsCache = null;
    lastUsedLine = null;
    lastError = null;
  }

  // ==================== 线路集合与排序 ====================

  static PlayLine? byId(String id) {
    for (final l in kPlayLines) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// 按测速分值升序（分值 = EMA 耗时 + 连续失败惩罚），最快在前
  static List<PlayLine> orderedLines() {
    final list = [...kPlayLines];
    list.sort((a, b) => scoreOf(a).compareTo(scoreOf(b)));
    return list;
  }

  /// 线路分值（越小越优先）
  static double scoreOf(PlayLine line) {
    final st = statOf(line.id);
    return (st.emaMs ?? _unknownScore) + st.fails * _failPenalty;
  }

  static PlayLineStat statOf(String id) {
    final s = _stats()[id];
    if (s is! Map) return const PlayLineStat();
    return PlayLineStat(
      emaMs: (s['ema'] as num?)?.toDouble(),
      ok: (s['ok'] as num?)?.toInt() ?? 0,
      fails: (s['fail'] as num?)?.toInt() ?? 0,
    );
  }

  // ==================== 入口 ====================

  /// 解析 [title] 第 [episodeIndex] 集的可播放直链。
  ///
  /// 手动锁定线路（或显式传 [onLine]）时只走该线路；否则按测速顺序分批并发
  /// 竞速，首个成功返回。
  static Future<String> resolve({
    required String title,
    required int episodeIndex,
    PlayLine? onLine,
  }) async {
    lastError = null;
    final pinned = onLine?.id ?? _pinnedLineId();

    if (pinned.isNotEmpty) {
      final line = onLine ?? byId(pinned);
      if (line != null) {
        try {
          final url = await _resolveOnLine(line, title, episodeIndex);
          lastUsedLine = line;
          debugPlayLine('锁定线路 ${line.id} -> $url');
          return url;
        } catch (e) {
          lastError = '线路 ${line.name} 暂不可用（${_message(e)}）';
          throw Exception(lastError);
        }
      }
    }

    final lines = orderedLines();
    for (var i = 0; i < lines.length; i += _batchSize) {
      final batch = <Future<_Win?>>[];
      for (var j = i; j < lines.length && j < i + _batchSize; j++) {
        batch.add(_tryLine(lines[j], title, episodeIndex));
      }
      final win = await _firstSuccess(batch);
      if (win != null) {
        lastUsedLine = win.line;
        debugPlayLine('自动选中线路 ${win.line.id} -> ${win.url}');
        return win.url;
      }
    }

    lastError = '全部 ${lines.length} 条线路均解析失败（未收录或网络异常）';
    throw Exception(lastError);
  }

  /// 线路解析日志（输出到 logcat，便于排查当前用的是哪条线路）
  static void debugPlayLine(String msg) => debugPrint('[线路] $msg');

  static String _pinnedLineId() {
    try {
      return SettingsService.pinnedLineId;
    } catch (_) {
      return '';
    }
  }

  static String _message(Object e) {
    final s = e.toString();
    const prefix = 'Exception: ';
    final body = s.startsWith(prefix) ? s.substring(prefix.length) : s;
    return body.trim().isEmpty ? '解析失败' : body.trim();
  }

  /// 竞速包装：任何失败/超时都归为 null，不向外抛
  static Future<_Win?> _tryLine(PlayLine line, String title, int episodeIndex) async {
    try {
      final url = await _resolveOnLine(line, title, episodeIndex)
          .timeout(_lineTimeout);
      return _Win(line, url);
    } catch (_) {
      return null;
    }
  }

  /// 并发等待“第一个成功”，全部失败才返回 null
  static Future<_Win?> _firstSuccess(Iterable<Future<_Win?>> futures) {
    final completer = Completer<_Win?>();
    var pending = 0;
    for (final f in futures) {
      pending++;
      f.then((v) {
        if (v != null) {
          if (!completer.isCompleted) completer.complete(v);
        } else if (--pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }, onError: (Object _) {
        if (--pending == 0 && !completer.isCompleted) completer.complete(null);
      });
    }
    if (pending == 0) return Future<_Win?>.value(null);
    return completer.future;
  }

  // ==================== 单线路解析 ====================

  static Future<String> _resolveOnLine(
    PlayLine line,
    String title,
    int episodeIndex,
  ) async {
    final key = '${line.id}|$title|$episodeIndex';
    final hit = _cache[key];
    if (hit != null) return hit;

    final sw = Stopwatch()..start();
    final String url;
    try {
      url = line.mode == PlayLineMode.api
          ? await _resolveApi(line, title, episodeIndex)
          : await _resolveHtml(line, title, episodeIndex);
    } catch (e) {
      _recordFailure(line);
      rethrow;
    }
    sw.stop();
    _recordSuccess(line, sw.elapsedMilliseconds);

    if (_cache.length >= _maxCache) _cache.clear();
    _cache[key] = url;
    return url;
  }

  // ==================== API 模式 ====================

  static Future<String> _resolveApi(
    PlayLine line,
    String title,
    int episodeIndex,
  ) async {
    try {
      final dio = _client(line);
      String? reason;
      for (final kw in searchKeywords(title)) {
        final body = await _get(
            dio, '${line.base}/api.php/provide/vod/?ac=detail&wd=${Uri.encodeComponent(kw)}');
        if (body == null) {
          reason = '接口无响应';
          continue;
        }
        final decoded = _tryJson(body);
        final list = decoded is Map ? decoded['list'] : null;
        if (list is! List || list.isEmpty) {
          reason = '接口已关闭';
          continue;
        }
        final url = _pickEpisode(list, title, episodeIndex);
        if (url != null) return url;
        reason = '未收录第$episodeIndex集';
      }
      throw Exception(reason ?? '接口已关闭');
    } catch (_) {
      // API 关闭/未收录：转网页链路再试一次
      return _resolveHtml(line, title, episodeIndex);
    }
  }

  /// 从接口结果里挑目标剧的第 [episodeIndex] 集直链（剧名完全一致者优先）
  static String? _pickEpisode(List<dynamic> items, String title, int ep) {
    final t = normalizeTitle(title);
    String? partial;
    for (final item in items) {
      if (item is! Map) continue;
      final name = item['vod_name']?.toString() ?? '';
      if (!nameMatches(name, title)) continue;
      final url =
          episodeFromPlayUrl(item['vod_play_url']?.toString(), ep);
      if (url == null) continue;
      if (normalizeTitle(name) == t) return url;
      partial ??= url;
    }
    return partial;
  }

  // ==================== 网页模式 ====================

  static Future<String> _resolveHtml(
    PlayLine line,
    String title,
    int episodeIndex,
  ) async {
    final dio = _client(line);
    String? reason;
    for (final kw in searchKeywords(title)) {
      final search = await _get(dio,
          '${line.base}/vodsearch/-------------.html?wd=${Uri.encodeComponent(kw)}');
      if (search == null) {
        reason = '搜索页无响应';
        continue;
      }

      final ids = _candidatesFromSearch(search, title);
      if (ids.isEmpty) {
        reason = '搜索无结果';
        continue;
      }

      for (var i = 0; i < ids.length; i++) {
        final id = ids[i];
        final detail = await _get(dio, '${line.base}/voddetail/$id.html');
        if (detail != null) {
          final dt = _pageTitle(detail);
          // 详情页剧名与目标不符：该候选是推荐位/缓存错页，跳过（含直拼兜底）
          if (dt != null && dt.isNotEmpty && !nameMatches(dt, title)) continue;
          final path = _epPathFromDetail(detail, id, episodeIndex);
          if (path != null) {
            final url = await _m3u8FromPlay(dio, '${line.base}/$path');
            if (url != null) return url;
          }
          if (i == 0) {
            final direct = await _m3u8FromPlay(
                dio, '${line.base}/vodplay/$id-1-$episodeIndex.html');
            if (direct != null) return direct;
          }
          continue;
        }
        // 详情页不可用：首个已验名候选直拼播放页（部分站无详情页）
        if (i == 0) {
          final direct = await _m3u8FromPlay(
              dio, '${line.base}/vodplay/$id-1-$episodeIndex.html');
          if (direct != null) return direct;
        }
      }
      reason = '未收录第$episodeIndex集';
    }
    throw Exception(reason ?? '搜索无结果');
  }

  /// 生成搜索关键词（maccms `wd` 是裸 LIKE：站名含空格/标点时整串标题必失败，
  /// 依次用去后缀、去标点片段、无标点前缀重试）
  static List<String> searchKeywords(String title) {
    final out = <String>[];
    void add(String s) {
      final v = s.trim();
      if (v.length < 2 || out.contains(v) || out.length >= _maxKeywords) return;
      out.add(v);
    }

    final noSuffix = title.replaceFirst(
        RegExp(r'第[0-9零一二三四五六七八九十百]+[季部期]$'), '');
    String segOf(String s) {
      final parts = s
          .split(RegExp(r'[!！,，.。:：、;；\s]+'))
          .where((e) => e.length >= 4)
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      return parts.isEmpty ? '' : parts.first;
    }

    add(title);
    add(noSuffix);
    add(segOf(noSuffix));
    add(segOf(title));
    for (final base in <String>{title, noSuffix}) {
      for (var k = base.length - 1; k >= 4 && out.length < _maxKeywords; k--) {
        final p = base.substring(0, k);
        if (RegExp(r'[!！,，.。:：、;；\s]').hasMatch(p)) continue;
        add(p);
      }
    }
    return out;
  }

  /// 搜索页 HTML → 校验过剧名的候选 id（完全一致者优先，最多 [_maxCandidates] 个）
  ///
  /// 只接受「链接 + 名称（title 属性或 <b> 文本）」都匹配的条目，
  /// 避免把「最新更新/热播影视」等推荐位当结果（会播放成别的剧）。
  static List<String> _candidatesFromSearch(String html, String title) {
    final exact = <String>[];
    final partial = <String>[];
    final seen = <String>{};
    final t = normalizeTitle(title);

    void consider(String id, String name) {
      if (id.isEmpty || seen.contains(id) || !nameMatches(name, title)) return;
      seen.add(id);
      if (normalizeTitle(name) == t) {
        if (!exact.contains(id)) exact.add(id);
      } else if (!partial.contains(id)) {
        partial.add(id);
      }
    }

    for (final m
        in RegExp(r'<a\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final tag = m.group(0)!;
      final href =
          RegExp(r'href="([^"]+)"', caseSensitive: false)
              .firstMatch(tag)
              ?.group(1) ??
          '';
      if (!RegExp(r'/(?:vodplay|voddetail)/').hasMatch(href)) continue;
      var name = RegExp(r'title="([^"]*)"', caseSensitive: false)
              .firstMatch(tag)
              ?.group(1)
              ?.trim() ??
          '';
      if (name.isEmpty) {
        // 部分模板把名称放在锚点内部的 <b> 里
        final end = html.length < m.end + 240 ? html.length : m.end + 240;
        final b = RegExp(r'<b>([^<]+)</b>').firstMatch(html.substring(m.end, end));
        name = b?.group(1)?.trim() ?? '';
      }
      if (name.isEmpty) continue;
      final id = RegExp(r'voddetail/([0-9a-zA-Z_\-]+)\.html').firstMatch(href)?.group(1) ??
          RegExp(r'vodplay/([0-9a-zA-Z_\-]+)-\d+-\d+\.html')
              .firstMatch(href)
              ?.group(1);
      if (id == null) continue;
      consider(id, name);
    }

    final out = <String>[...exact, ...partial];
    return out.length > _maxCandidates
        ? out.sublist(0, _maxCandidates)
        : out;
  }

  /// 页面 `<title>`（去掉常见实体），失败返回 null
  static String? _pageTitle(String html) {
    final m = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false)
        .firstMatch(html);
    if (m == null) return null;
    return (m.group(1) ?? '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .trim();
  }

  /// 详情页 → 目标集的播放页相对路径（同集多线路取线路号最小者）
  static String? _epPathFromDetail(String html, String id, int episodeIndex) {
    String? best;
    var bestSid = 1 << 30;
    for (final m
        in RegExp(r'vodplay/([0-9a-zA-Z_\-]+)-(\d+)-(\d+)\.html').allMatches(html)) {
      if (m.group(1) != id) continue;
      if (int.tryParse(m.group(3) ?? '') != episodeIndex) continue;
      final sid = int.tryParse(m.group(2) ?? '') ?? 1 << 30;
      if (sid < bestSid) {
        bestSid = sid;
        best = m.group(0);
      }
    }
    return best;
  }

  static Future<String?> _m3u8FromPlay(Dio dio, String url) async {
    final html = await _get(dio, url);
    if (html == null) return null;
    return extractPlayUrl(html);
  }

  // ==================== 播放页取链（纯函数，可单测） ====================

  /// 播放页 HTML → 可直接播放的地址
  ///
  /// 优先 `player_aaaa`（或 `player_data`）JSON 的 `url` 字段——用括号配平扫描取
  /// JSON（部分站结尾没有分号，且对象内含嵌套对象/字符串里的花括号）；
  /// 依次回退：JSON 里的 m3u8 → 页面上的 m3u8 直链 → JSON 里首个 http 直链。
  static String? extractPlayUrl(String html) {
    final json = _balancedObject(html, 'player_aaaa') ??
        _balancedObject(html, 'player_data');
    List<String> cands = const <String>[];
    if (json != null) {
      cands = RegExp(r'"url"\s*:\s*"([^"]+)"')
          .allMatches(json)
          .map((m) => _unescape(m.group(1) ?? ''))
          .where((u) => u.startsWith('http'))
          .toList();
      for (final u in cands) {
        if (u.contains('.m3u8')) return u;
      }
    }
    final raw = RegExp(r'''https?://[^\s"'<>\\]+\.m3u8[^\s"'<>\\]*''')
        .firstMatch(html)
        ?.group(0);
    if (raw != null) return raw;
    if (cands.isNotEmpty) return cands.first;
    return null;
  }

  /// 从 `varName={...}` 起做括号配平扫描，返回对象字面量（不含分号）
  static String? _balancedObject(String text, String varName) {
    final idx = text.indexOf(varName);
    if (idx < 0) return null;
    final start = text.indexOf('{', idx);
    if (start < 0) return null;

    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var i = start; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == 0x5C) {
          esc = true;
        } else if (c == 0x22) {
          inStr = false;
        }
        continue;
      }
      if (c == 0x22) {
        inStr = true;
      } else if (c == 0x7B) {
        depth++;
      } else if (c == 0x7D) {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  /// maccms `vod_play_url` → 第 [episodeIndex] 集直链
  ///
  /// 格式：`线路1名$url1#url2...$$$线路2名$...`（多线路以 `$$$` 分隔，
  /// 集以 `#` 分隔，单条为 `集名$url`）。
  static String? episodeFromPlayUrl(String? vodPlayUrl, int episodeIndex) {
    if (vodPlayUrl == null || vodPlayUrl.isEmpty || episodeIndex < 1) {
      return null;
    }
    for (final group in vodPlayUrl.split(r'$$$')) {
      final eps = group.split('#');
      if (eps.length < episodeIndex) continue;
      final entry = _unescape(eps[episodeIndex - 1].trim());
      if (entry.startsWith('http')) return entry;
      final dollar = entry.indexOf(r'$');
      if (dollar < 0) continue;
      final url = entry.substring(dollar + 1).trim();
      if (url.startsWith('http')) return url;
    }
    return null;
  }

  /// 搜索结果/详情名与目标标题是否匹配（忽略标点空白）
  ///
  /// 完全一致恒匹配；否则要求较短一方至少 4 个字符，避免短词误配别的剧。
  static bool nameMatches(String name, String title) {
    if (name.isEmpty || title.isEmpty) return false;
    final n = normalizeTitle(name);
    final t = normalizeTitle(title);
    if (n.isEmpty || t.isEmpty) return false;
    if (n == t) return true;
    if (n.contains(t)) return true;
    return t.contains(n) && n.length >= 4;
  }

  /// 标题归一化：去空白与中英文标点（供剧名比对/去重复用）
  static String normalizeTitle(String s) => s.replaceAll(
        RegExp(r'''[\s\-—–·:：!！?？,，.。;；'"“”《》「」『』（）()【】\[\]]+'''),
        '',
      );

  static String _unescape(String s) =>
      s.replaceAll(r'\/', '/').replaceAll(r'\u002F', '/').replaceAll(r'\u002f', '/');

  // ==================== HTTP ====================

  static Dio _client(PlayLine line) => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (code) => code != null && code < 500,
        headers: {
          'user-agent': ApiConstants.browserUserAgent,
          'accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'accept-language': 'zh-CN,zh;q=0.9',
          'referer': '${line.base}/',
        },
      ));

  static Future<String?> _get(Dio dio, String url) async {
    try {
      final resp = await dio.get<dynamic>(url);
      final body = resp.data?.toString() ?? '';
      if (body.isEmpty) return null;
      return body;
    } catch (_) {
      return null;
    }
  }

  static dynamic _tryJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  // ==================== 测速统计持久化 ====================

  static Map<String, dynamic> _stats() {
    if (_statsCache != null) return _statsCache!;
    try {
      final raw = StorageService.getString(AppConstants.keyPlayLineStats);
      if (raw.isNotEmpty) {
        final v = jsonDecode(raw);
        if (v is Map) {
          _statsCache = v.cast<String, dynamic>();
          return _statsCache!;
        }
      }
    } catch (_) {
      // 未初始化/数据损坏：按空统计处理
    }
    _statsCache = <String, dynamic>{};
    return _statsCache!;
  }

  static Future<void> _persistStats() async {
    try {
      await StorageService.setString(
        AppConstants.keyPlayLineStats,
        jsonEncode(_statsCache ?? const <String, dynamic>{}),
      );
    } catch (_) {
      // 持久化失败不影响本次播放
    }
  }

  static void _recordSuccess(PlayLine line, int ms) {
    final stats = _stats();
    final prev = stats[line.id];
    final cur = prev is Map
        ? Map<String, dynamic>.from(prev)
        : <String, dynamic>{};
    final ema = (cur['ema'] as num?)?.toDouble();
    cur['ema'] = ema == null ? ms.toDouble() : ema * 0.6 + ms * 0.4;
    cur['ok'] = ((cur['ok'] as num?)?.toInt() ?? 0) + 1;
    cur['fail'] = 0;
    stats[line.id] = cur;
    _persistStats();
  }

  static void _recordFailure(PlayLine line) {
    final stats = _stats();
    final prev = stats[line.id];
    final cur = prev is Map
        ? Map<String, dynamic>.from(prev)
        : <String, dynamic>{};
    cur['fail'] = (((cur['fail'] as num?)?.toInt() ?? 0) + 1).clamp(0, 99).toInt();
    stats[line.id] = cur;
    _persistStats();
  }
}
