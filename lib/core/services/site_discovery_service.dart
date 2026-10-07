import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/api_constants.dart';
import 'play_lines.dart';

/// 候选站点的发现来源
enum DiscoverySource {
  /// 搜索引擎结果页（DuckDuckGo / Bing）
  engine,

  /// GitHub 仓库搜索（homepage / 描述文本）
  github,

  /// 可用站点首页的友情链接
  friend,

  /// 用户粘贴的订阅地址
  subscription,
}

extension DiscoverySourceLabel on DiscoverySource {
  String get label => switch (this) {
        DiscoverySource.engine => '搜索',
        DiscoverySource.github => 'GitHub',
        DiscoverySource.friend => '友链',
        DiscoverySource.subscription => '订阅',
      };
}

/// 候选站点状态
enum CandidateStatus {
  /// 已入池、排队待探测
  pending,

  /// 探测中
  probing,

  /// 探测通过（可勾选加入）
  ok,

  /// 探测失败
  failed,

  /// 站点库里已有（内置或自定义，不可勾选）
  known,
}

/// 一个被发现的候选站点。
///
/// 入池时只有地址与来源；探测后填充 [mode] / [latencyMs] / [sampleTitle]，
/// 或 [failReason]。状态变化后对象本身即最新值（页面直接持有引用刷新）。
class SiteCandidate {
  SiteCandidate({
    required this.base,
    required this.host,
    required this.source,
    this.status = CandidateStatus.pending,
    this.priority = 1,
  });

  /// 站点根地址（origin，形如 `https://example.com`）
  final String base;

  /// 展示用主机名
  final String host;

  /// 订阅条目自带的名称（有则优先展示）
  String? name;

  final DiscoverySource source;

  /// 置信度：0=地址里直接写了接口/详情路径，1=搜索结果，
  /// 2=仓库主页/描述，3=友链。越小越先探测。
  final int priority;

  CandidateStatus status;
  PlayLineMode? mode;
  int? latencyMs;
  String? sampleTitle;
  String? failReason;
  bool selected = false;

  bool get selectable => status == CandidateStatus.ok;

  String get displayName => (name?.isNotEmpty ?? false) ? name! : host;
}

/// 一次发现请求的配置
class DiscoveryRequest {
  const DiscoveryRequest({
    required this.keyword,
    this.useEngine = true,
    this.useGithub = true,
    this.useFriend = true,
  });

  /// 查找关键词（会拼进搜索引擎查询串）
  final String keyword;

  /// 是否用搜索引擎找种子
  final bool useEngine;

  /// 是否用 GitHub 仓库搜索找种子
  final bool useGithub;

  /// 是否沿可用站点的友情链接扩展
  final bool useFriend;
}

/// 搜索引擎（结果页均为服务端渲染 HTML，无需 JS）
enum SearchEngine {
  duckduckgo('DuckDuckGo'),
  bing('Bing');

  const SearchEngine(this.label);

  final String label;

  String url(String query) => switch (this) {
        SearchEngine.duckduckgo =>
          'https://html.duckduckgo.com/html/?q=${Uri.encodeQueryComponent(query)}',
        SearchEngine.bing =>
          'https://www.bing.com/search?setlang=zh-hans&count=30&q=${Uri.encodeQueryComponent(query)}',
      };
}

/// 动态在线查找资源站点 / API。
///
/// 三类来源并发取种子（搜索引擎结果页、GitHub 仓库搜索、可用站点友链），
/// 归一化去重后批量探测（先标准接口、后网页解析），全部结果流式回调给 UI。
/// **不内置任何默认站点清单或订阅地址**——站点库的种子一律来自当次联网查找。
class SiteDiscoveryService {
  SiteDiscoveryService._();

  /// 单站探测超时（要覆盖「标准接口 + 网页解析」两轮尝试）
  static const Duration _probeTimeout = Duration(seconds: 18);

  /// 抓取（搜索结果页 / 首页 / 订阅）超时
  static const Duration _fetchTimeout = Duration(seconds: 12);

  /// 探测并发
  static const int _probeConcurrency = 5;

  /// 候选池上限（防止友链扩展无限膨胀）
  static const int _maxCandidates = 90;

  /// 单次发现最多深挖几个仓库 README（GitHub 核心 API 匿名 60 次/时）
  /// 每次查找最多深挖多少个仓库 README（三类查询共用）
  static const int _readmeBudget = 10;

  /// 参与友链扩展的可用站点数
  static const int _friendSeeds = 8;

  /// 友链扩展最多新增的候选数
  static const int _friendExpandLimit = 20;

  // ==================== 测试注入点 ====================

  /// 替换整段发现流程（widget 测试用，返回固定候选列表）
  @visibleForTesting
  static Future<List<SiteCandidate>> Function(DiscoveryRequest request)?
      debugDiscover;

  /// 替换订阅地址拉取（widget 测试用）
  @visibleForTesting
  static Future<String?> Function(String url)? debugFetchText;

  /// 替换单站探测（widget 测试用）
  @visibleForTesting
  static Future<AutoProbeResult> Function(String base)? debugProbe;

  // ==================== 发现主流程 ====================

  /// 从公网查找候选站点并探测可用性。
  ///
  /// [onUpdate] 每次状态变化回调最新快照（边找边出）；
  /// [onNote] 回调各来源的降级/汇总提示；[isCancelled] 返回 true 即中止。
  static Future<List<SiteCandidate>> discover(
    DiscoveryRequest request, {
    void Function(List<SiteCandidate> snapshot)? onUpdate,
    void Function(String note)? onNote,
    bool Function()? isCancelled,
  }) async {
    final override = debugDiscover;
    if (override != null) return override(request);

    final cancelled = isCancelled ?? () => false;
    final knownKeys = knownHostKeys();
    final pool = <String, SiteCandidate>{};
    final notes = <String>{};
    var knownShown = 0;

    void note(String msg) {
      if (!notes.add(msg)) return;
      debugPrint('[DISC] $msg');
      onNote?.call(msg);
    }

    List<SiteCandidate> snapshot() => sortCandidates(pool.values);

    List<SiteCandidate> offer(Iterable<String> bases, DiscoverySource source,
        {int priority = 1}) {
      final added = <SiteCandidate>[];
      for (final base in bases) {
        if (pool.length >= _maxCandidates) break;
        final key = hostKey(base);
        if (key == null || pool.containsKey(key)) continue;
        final known = knownKeys.contains(key);
        final c = SiteCandidate(
          base: base,
          host: Uri.tryParse(base)?.host ?? base,
          source: source,
          status: known ? CandidateStatus.known : CandidateStatus.pending,
          priority: priority,
        );
        if (known) knownShown++;
        pool[key] = c;
        added.add(c);
      }
      if (added.isNotEmpty) onUpdate?.call(snapshot());
      return added;
    }

    // ---- 阶段一：种子（搜索引擎 + GitHub 并发）----
    final seeds = <Future<void>>[];
    if (request.useEngine) {
      for (final engine in SearchEngine.values) {
        for (final query in engineQueries(request.keyword)) {
          seeds.add(() async {
            final body = await _fetch(engine.url(query));
            if (body == null) {
              note('${engine.label} 抓取失败（可能被拦截或无响应），已跳过该来源');
              return;
            }
            final bases = searchResultBases(body, engine: engine);
            final deep = maccmsApiBases(body);
            if (bases.isEmpty && deep.isEmpty) {
              note('${engine.label} 未解析到候选站点');
              return;
            }
            if (bases.isNotEmpty) offer(bases, DiscoverySource.engine);
            if (deep.isNotEmpty) offer(deep, DiscoverySource.engine, priority: 0);
          }());
        }
      }
    }
    if (request.useGithub) {
      var readmeBudget = _readmeBudget;
      for (final query in githubQueries(request.keyword)) {
        seeds.add(() async {
          final body = await _fetch(githubSearchUrl(query), github: true);
          if (body == null) {
            note('GitHub 搜索失败（可能触发限流），已跳过该来源');
            return;
          }
          final bases = githubRepoBases(body);
          if (bases.isNotEmpty) offer(bases, DiscoverySource.github, priority: 2);
          for (final repo in githubReadmeTargets(body, limit: 6)) {
            if (cancelled() || readmeBudget <= 0) return;
            readmeBudget--;
            final readme = await _fetch(
                'https://api.github.com/repos/$repo/readme',
                github: true,
                raw: true);
            if (readme == null) continue;
            final added = offer(maccmsApiBases(readme), DiscoverySource.github,
                priority: 0);
            if (added.isNotEmpty) {
              note('GitHub README 深挖：$repo 贡献 ${added.length} 个候选');
            }
          }
        }());
      }
    }
    await Future.wait(seeds);
    if (cancelled()) return snapshot();

    // ---- 阶段二：批量探测 ----
    final pending = [
      for (final c in pool.values)
        if (c.status == CandidateStatus.pending) c,
    ];
    await probeCandidates(pending, onUpdate: (items) => onUpdate?.call(snapshot()),
        isCancelled: isCancelled);
    if (cancelled()) return snapshot();

    // ---- 阶段三：沿本次搜索结果的站点首页扩展友链（种子只取本次结果）----
    if (request.useFriend) {
      // 种子优先级：已探测可用 > 已在库 > 其余（同档按置信度）。
      // 可用/已在库的站点本身就是 maccms 站，它们的友链命中率远高于
      // 还没探测过的候选（实测其余候选的友链大量是统计/社交/博客域）。
      int seedRank(SiteCandidate c) {
        if (c.status == CandidateStatus.ok) return 0;
        if (c.status == CandidateStatus.known) return 1;
        return 2;
      }

      final seeds = [
        for (final c in pool.values)
          if (c.source == DiscoverySource.engine ||
              c.source == DiscoverySource.github)
            c,
      ];
      seeds.sort((a, b) {
        final r = seedRank(a).compareTo(seedRank(b));
        if (r != 0) return r;
        return a.priority.compareTo(b.priority);
      });
      final friendSeeds = seeds.take(_friendSeeds);
      final expanded = <SiteCandidate>[];
      for (final seed in friendSeeds) {
        if (cancelled()) break;
        final html = await _fetch('${seed.base}/');
        if (html == null) continue;
        final added =
            offer(friendLinkBases(html, seed.base), DiscoverySource.friend,
                priority: 3);
        for (final c in added) {
          if (c.status == CandidateStatus.pending) expanded.add(c);
        }
        if (expanded.length >= _friendExpandLimit) break;
      }
      if (expanded.isNotEmpty) {
        note('沿 ${friendSeeds.length} 个搜索结果站点的友链扩展出 ${expanded.length} 个新候选');
        await probeCandidates(
          expanded.sublist(0, math.min(expanded.length, _friendExpandLimit)),
          onUpdate: (items) => onUpdate?.call(snapshot()),
          isCancelled: isCancelled,
        );
      }
    }

    final result = snapshot();
    final ok = result.where((c) => c.status == CandidateStatus.ok).length;
    note('查找完成：候选 ${result.length} 个 · 可用 $ok 个'
        '${knownShown > 0 ? ' · 已存在 $knownShown 个' : ''}');
    return result;
  }

  /// 批量探测 pending 候选（并发 [[_probeConcurrency]]，逐个回调进度）
  static Future<void> probeCandidates(
    List<SiteCandidate> items, {
    void Function(List<SiteCandidate> snapshot)? onUpdate,
    bool Function()? isCancelled,
  }) async {
    // 置信度高的先探测（同档保持传入顺序）
    final queue = <MapEntry<int, SiteCandidate>>[
      for (var i = 0; i < items.length; i++)
        if (items[i].status == CandidateStatus.pending) MapEntry(i, items[i]),
    ];
    if (queue.isEmpty) return;
    queue.sort((a, b) {
      final c = a.value.priority.compareTo(b.value.priority);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
    final queueBases = [for (final e in queue) e.value];
    final cancelled = isCancelled ?? () => false;
    final probe = debugProbe ?? PlayLineResolver.probeAuto;
    final all = List<SiteCandidate>.of(items);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        if (cancelled()) return;
        final i = next++;
        if (i >= queueBases.length) return;
        final c = queueBases[i];
        c.status = CandidateStatus.probing;
        onUpdate?.call(all);

        AutoProbeResult r;
        try {
          r = await probe(c.base).timeout(_probeTimeout);
        } on TimeoutException {
          r = AutoProbeResult(
              reason: '探测超时', latencyMs: _probeTimeout.inMilliseconds);
        } catch (e) {
          r = AutoProbeResult(reason: '检测失败：${_message(e)}');
        }
        if (cancelled()) return;
        c.latencyMs = r.latencyMs;
        if (r.ok) {
          c.status = CandidateStatus.ok;
          c.mode = r.mode;
          c.sampleTitle = r.sampleTitle;
          c.selected = true;
        } else {
          c.status = CandidateStatus.failed;
          c.failReason = r.reason ?? '不可用';
        }
        onUpdate?.call(all);
      }
    }

    await Future.wait([
      for (var i = 0; i < _probeConcurrency; i++) worker(),
    ]);
  }

  // ==================== 订阅导入 ====================

  /// 拉取订阅地址正文（失败返回 null；测试可注入 [debugFetchText]）
  static Future<String?> fetchText(String url) => _fetch(url);

  /// 订阅 JSON → 候选列表。
  ///
  /// 兼容 `{"sites":[...]}` 与顶层数组两种形态；条目地址字段宽容
  /// （`base`/`url`/`site`/`host`/`api` 任一），名称取 `name`/`title`。
  /// 模式一律交给探测自动判定，不采信订阅里的 mode 标注。
  /// 格式非法或没有可用地址时抛 [FormatException]。
  static List<SiteCandidate> parseSubscription(String jsonText) {
    final data = jsonDecode(jsonText);
    final List<dynamic> rawList;
    if (data is List) {
      rawList = data;
    } else if (data is Map) {
      final v = data['sites'] ?? data['lines'] ?? data['data'];
      if (v is! List) {
        throw const FormatException('缺少 sites 数组');
      }
      rawList = v;
    } else {
      throw const FormatException('无法识别的订阅格式');
    }

    final out = <SiteCandidate>[];
    final seen = <String>{};
    for (final e in rawList) {
      if (e is! Map) continue;
      final rawBase = _firstText(e, const ['base', 'url', 'site', 'host', 'api']);
      if (rawBase == null) continue;
      final base = candidateBase(rawBase);
      if (base == null) continue;
      final key = hostKey(base);
      if (key == null || !seen.add(key)) continue;
      final host = Uri.tryParse(base)?.host ?? base;
      out.add(SiteCandidate(
        base: base,
        host: host,
        source: DiscoverySource.subscription,
      )..name = _firstText(e, const ['name', 'title']));
    }
    if (out.isEmpty) throw const FormatException('订阅里没有可用的站点地址');
    return out;
  }

  /// 把一批候选并入现有列表：同主机去重、已存在的标记为 [CandidateStatus.known]
  static List<SiteCandidate> mergeCandidates(
    List<SiteCandidate> current,
    Iterable<SiteCandidate> incoming,
  ) {
    final out = List<SiteCandidate>.of(current);
    final seen = <String>{for (final c in out) _keyOf(c.base)};
    final known = knownHostKeys();
    for (final c in incoming) {
      if (!seen.add(_keyOf(c.base))) continue;
      if (known.contains(_keyOf(c.base))) c.status = CandidateStatus.known;
      out.add(c);
    }
    return sortCandidates(out);
  }

  // ==================== 结果整理 ====================

  /// 排序：可用优先 → 探测中 → 待探测 → 已存在 → 失败；同档按主机名
  static List<SiteCandidate> sortCandidates(Iterable<SiteCandidate> items) {
    final list = List<SiteCandidate>.of(items);
    int rank(CandidateStatus s) => switch (s) {
          CandidateStatus.ok => 0,
          CandidateStatus.probing => 1,
          CandidateStatus.pending => 2,
          CandidateStatus.known => 3,
          CandidateStatus.failed => 4,
        };
    list.sort((a, b) {
      final c = rank(a.status).compareTo(rank(b.status));
      if (c != 0) return c;
      return a.host.toLowerCase().compareTo(b.host.toLowerCase());
    });
    return list;
  }

  /// 站点库里已知的主机键（内置 + 自定义 + 官方源）
  static Set<String> knownHostKeys() {
    final out = <String>{};
    try {
      for (final line in PlayLineResolver.allLines) {
        final k = hostKey(line.base);
        if (k != null) out.add(k);
      }
    } catch (_) {
      // 存储未初始化：只留官方源
    }
    final official = hostKey(ApiConstants.webBase);
    if (official != null) out.add(official);
    return out;
  }

  // ==================== 查询串 ====================

  /// 关键词 → 搜索引擎查询串（首条是接口路径的精确短语，命中精度最高）
  static List<String> engineQueries(String keyword) {
    final k = keyword.trim();
    return [
      '"api.php/provide/vod"',
      if (k.isNotEmpty) 'maccms 采集接口 $k',
    ];
  }

  /// 关键词 → GitHub 仓库搜索查询串（匿名限流 10 次/分，控制在 3 条内）。
  /// `in:readme` 让结果指向「README 里写了接口地址」的仓库，深挖价值最高。
  static List<String> githubQueries(String keyword) {
    final k = keyword.trim();
    return [
      '"api.php/provide/vod" in:readme',
      'maccms api.php provide vod in:readme',
      if (k.isNotEmpty) 'maccms $k in:readme',
    ];
  }

  static String githubSearchUrl(String query) =>
      'https://api.github.com/search/repositories?sort=stars&per_page=20'
      '&q=${Uri.encodeQueryComponent(query)}';

  // ==================== 解析（纯函数，离线可测） ====================

  static final RegExp _hrefRe =
      RegExp(r'''href\s*=\s*["']([^"']+)["']''', caseSensitive: false);

  /// HTML → 全部 href 原文（保持出现顺序）
  static List<String> extractLinks(String html) =>
      [for (final m in _hrefRe.allMatches(html)) (m.group(1) ?? '').trim()];

  /// href → 绝对地址（相对链接/锚点/脚本返回 null）
  static String? absolutize(String href) {
    var s = href.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('//')) return 'https:$s';
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return _trimTail(s);
    }
    if (s.startsWith('/') || s.startsWith('#') || s.startsWith('?')) return null;
    if (RegExp(r'^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}(?:[/?#]|$)', caseSensitive: false)
        .hasMatch(s)) {
      return 'https://${_trimTail(s)}';
    }
    return null;
  }

  /// 搜索结果页链接 → 直达地址。
  ///
  /// 先绝对化，再还原搜索引擎跳转（DuckDuckGo `uddg`、Bing `u=a1<base64>`）；
  /// 属于跳转却解不出来时返回 null。
  static String? directUrl(String href) {
    final abs = absolutize(href);
    if (abs == null) return null;
    final uri = Uri.tryParse(abs);
    if (uri == null) return abs;
    final host = uri.host.toLowerCase();
    if (host == 'duckduckgo.com' && uri.path.startsWith('/l/')) {
      final target = uri.queryParameters['uddg'];
      return (target == null || target.isEmpty) ? null : target;
    }
    if (host.endsWith('bing.com') && uri.path.startsWith('/ck/')) {
      final u = uri.queryParameters['u'];
      if (u == null || !u.startsWith('a1')) return null;
      return _base64UrlDecode(u.substring(2));
    }
    return abs;
  }

  /// 搜索结果页 HTML → 候选站点地址（优先只取结果区，取不到再回退全页）
  static List<String> searchResultBases(String html, {SearchEngine? engine}) {
    final hrefs = switch (engine) {
      SearchEngine.duckduckgo => _linksOfClass(html, 'result__a'),
      SearchEngine.bing => _linksInBingResults(html),
      null => extractLinks(html),
    };
    final urls = <String>[];
    for (final href in hrefs.isNotEmpty ? hrefs : extractLinks(html)) {
      final u = directUrl(href);
      if (u != null) urls.add(u);
    }
    return normalizeBases(urls);
  }

  /// 带指定 class 的 `<a>` 里的 href（搜索引擎结果条目的主链接）
  static List<String> _linksOfClass(String html, String cls) {
    final classRe = RegExp('class="[^"]*$cls[^"]*"', caseSensitive: false);
    final hrefRe = RegExp(r'''href\s*=\s*["']([^"']+)["']''',
        caseSensitive: false);
    final out = <String>[];
    for (final m in RegExp(r'<a\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final tag = m.group(0)!;
      if (!classRe.hasMatch(tag)) continue;
      final href = hrefRe.firstMatch(tag)?.group(1)?.trim();
      if (href != null && href.isNotEmpty) out.add(href);
    }
    return out;
  }

  /// Bing 有机结果（`<li class="b_algo">`）里每条的主链接，
  /// 避免把页脚导航、备案号、相关搜索等无关链接当候选
  static List<String> _linksInBingResults(String html) {
    const marker = '<li class="b_algo"';
    if (!html.contains(marker)) return const [];
    final out = <String>[];
    final h2Re = RegExp(
      r'''<h2[^>]*>\s*<a\b[^>]*href\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
      dotAll: true,
    );
    final anyRe = RegExp(r'''href\s*=\s*["']([^"']+)["']''',
        caseSensitive: false);
    for (final part in html.split(marker).skip(1)) {
      final m = h2Re.firstMatch(part) ?? anyRe.firstMatch(part);
      final href = m?.group(1)?.trim();
      if (href != null && href.isNotEmpty) out.add(href);
    }
    return out;
  }

  /// 站点首页 HTML → 友链候选（同主机内链剔除）
  static List<String> friendLinkBases(String html, String base) {
    final self = hostKey(base);
    final urls = <String>[];
    for (final href in extractLinks(html)) {
      final u = directUrl(href);
      if (u == null) continue;
      if (hostKey(u) == self) continue;
      urls.add(u);
    }
    return normalizeBases(urls);
  }

  /// GitHub 搜索响应 → 候选站点地址（homepage + 描述里的域名）
  static List<String> githubRepoBases(String jsonText) {
    try {
      final data = jsonDecode(jsonText);
      if (data is! Map) return const [];
      final items = data['items'];
      if (items is! List) return const [];
      final urls = <String>[];
      for (final it in items) {
        if (it is! Map) continue;
        final home = it['homepage']?.toString().trim() ?? '';
        if (home.isNotEmpty && home != 'null') urls.add(home);
        final text = '${it['description'] ?? ''} ${it['full_name'] ?? ''}';
        urls.addAll(urlsInText(text));
      }
      return normalizeBases(urls);
    } catch (_) {
      return const [];
    }
  }

  /// GitHub 搜索响应 → 要深挖 README 的仓库全名（最多 [limit] 个）。
  /// 只挑名字/描述确实是「影视·采集·接口」类的仓库，避免大型榜单/工具仓库
  /// 的 README 带出成百上千个无关域名。
  static final RegExp _readmeHintRe = RegExp(
      r'maccms|vod|tv|video|movie|film|iptv|影视|视频|采集|短剧|直播|接口');

  static List<String> githubReadmeTargets(String jsonText, {int limit = 4}) {
    try {
      final data = jsonDecode(jsonText);
      if (data is! Map) return const [];
      final items = data['items'];
      if (items is! List) return const [];
      final out = <String>[];
      for (final it in items) {
        if (it is! Map) continue;
        final name = it['full_name']?.toString().trim() ?? '';
        if (name.isEmpty || name == 'null' || !name.contains('/')) continue;
        if (!RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(name)) continue;
        final desc = it['description']?.toString() ?? '';
        final hay = '$name $desc'.toLowerCase();
        if (!_readmeHintRe.hasMatch(hay)) continue;
        out.add(name);
        if (out.length >= limit) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// 自由文本 → 里面的域名/URL（GitHub 描述、README 片段等）
  static List<String> urlsInText(String text) {
    final re = RegExp(
      r'''(?:https?://)?[a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)+(?::\d{2,5})?(?:/[^\s"'<>]*)?''',
      caseSensitive: false,
    );
    return normalizeBases([for (final m in re.allMatches(text)) m.group(0)!]);
  }

  /// maccms 接口/详情路径（出现在正文里基本可断定是可用站点）
  static final RegExp _vodPathRe = RegExp(
      r'/(?:api\.php/provide/vod|voddetail|vodplay|vodsearch)',
      caseSensitive: false);

  /// 正文里明确带 maccms 路径的地址 → 站点 origin（置信度最高的候选来源）。
  ///
  /// 例：`https://api.xxx.com/api.php/provide/vod/?ac=list` → `https://api.xxx.com`。
  /// 用于 GitHub README、搜索结果页这类「罗列采集接口」的文档。
  static List<String> maccmsApiBases(String text) {
    final re = RegExp(r'''(?:https?:)?//[^\s"'<>)\[\]{}\\,;`]+''',
        caseSensitive: false);
    final out = <String>[];
    for (final m in re.allMatches(text)) {
      var s = m.group(0)!;
      if (!_vodPathRe.hasMatch(s)) continue;
      if (s.startsWith('//')) s = 'https:$s';
      out.add(s);
    }
    return normalizeBases(out);
  }

  /// 一批链接 → 归一化站点地址（origin），过滤非法/无关域名并按主机去重
  static List<String> normalizeBases(Iterable<String> urls) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in urls) {
      final base = candidateBase(raw);
      if (base == null) continue;
      final key = hostKey(base);
      if (key == null || !seen.add(key)) continue;
      out.add(base);
    }
    return out;
  }

  /// 单条链接 → 可用作站点根地址的 origin（不可用返回 null）
  static String? candidateBase(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('//')) s = 'https:$s';
    if (s.startsWith('/') || s.startsWith('#') || s.startsWith('?')) return null;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      if (!RegExp(r'^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}(?:[/?#]|$)',
              caseSensitive: false)
          .hasMatch(s)) {
        return null;
      }
      s = 'https://$s';
    }
    s = _trimTail(s);
    final uri = Uri.tryParse(s);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    if (!_plausibleHost(host)) return null;
    try {
      return uri.origin.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  /// 主机键（去 `www.` 前缀，供去重/比对）；无法解析返回 null
  static String? hostKey(String base) {
    final host = Uri.tryParse(base)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  static String _keyOf(String base) => hostKey(base) ?? base.toLowerCase();

  /// 主机是否像一个真实站点（域名规则 + 排除搜索引擎/门户/代码托管等无关域）
  static bool _plausibleHost(String host) {
    if (host.isEmpty) return false;
    if (_ipv4(host)) return !_blocked(host);
    if (!RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?'
            r'(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$')
        .hasMatch(host)) {
      return false;
    }
    final tld = host.split('.').last;
    if (tld.length < 2 || !RegExp(r'^[a-z]+$').hasMatch(tld)) return false;
    if (_badTlds.contains(tld)) return false;
    return !_blocked(host);
  }

  static bool _ipv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return false;
    }
    return true;
  }

  static bool _blocked(String host) {
    for (final b in _blockedHosts) {
      if (host == b || host.endsWith('.$b')) return true;
    }
    for (final p in _blockedPrefixes) {
      if (host.startsWith(p)) return true;
    }
    return false;
  }

  /// 站点候选永远不需要的域名（搜索引擎、门户、代码托管、视频站…）
  static const Set<String> _blockedHosts = {
    'duckduckgo.com', 'bing.com', 'google.com', 'googleapis.com',
    'gstatic.com', 'yahoo.com', 'yandex.com', 'baidu.com', 'sogou.com',
    'so.com', '360.cn', 'github.com', 'githubusercontent.com', 'gitee.com',
    'gitcode.com', 'gitlab.com', 'bitbucket.org', 'sourceforge.net',
    'microsoft.com', 'apple.com', 'mozilla.org', 'wikipedia.org',
    'archive.org', 'reddit.com', 'twitter.com', 'x.com', 'facebook.com',
    'instagram.com', 'youtube.com', 'stackoverflow.com', 'medium.com',
    'npmjs.com', 'zhihu.com', 'juejin.cn', 'csdn.net', 'jianshu.cn',
    'segmentfault.com', 'cnblogs.com', 'iteye.com',
    'qq.com', 'weixin.qq.com', 'bilibili.com', 'douyin.com',
    'kuaishou.com', 'xiaohongshu.com', 'weibo.com', 'zcool.com.cn',
    'ithome.com', 'sohu.com', 'ifeng.com', 'douban.com', 'sina.com.cn',
    '163.com', '163.net', 'toutiao.com', 'iqiyi.com', 'youku.com',
    'pptv.com', 'le.com', 'mgtv.com', 'hongguoduanju.com',
    'gov.cn', 'edu.cn', 'mil.cn', 'ac.cn', 'gov', 'edu',
    'w3.org', 'schema.org', 'whatwg.org', 'ietf.org', 'iana.org',
    'miit.gov.cn', 'beian.gov.cn', '12321.cn', 'caict.ac.cn',
    'shields.io', 'badgen.net', 'badge.fury.io', 'travis-ci.com',
    'travis-ci.org', 'circleci.com', 'coveralls.io', 'codeclimate.com',
    'sonarcloud.io', 'snyk.io', 'david-dm.org', 'renovatebot.com',
    'github.io', 'pages.dev', 'vercel.app', 'netlify.com', 'herokuapp.com',
    'readthedocs.io', 'readthedocs.org', 'pypi.org', 'pub.dev', 'crates.io',
    'nodeseek.com', 'v2ex.com', 'linux.do', 'download.csdn.net',
    // 占位/社交/博客平台：友链里高频出现，实测探测全废
    'example.com', 'example.org', 'example.net', 'xxx.com',
    't.me', 'telegram.me', 'telegram.org',
    'typecho.org', 'browsehappy.com', 'wowslider.net',
    'wordpress.org', 'blogger.com', 'wix.com', 'squarespace.com',
    'shopify.com', 'jquery.com', 'jsdelivr.net', 'unpkg.com',
    'cloudflare.com', 'gravatar.com', 'cnzz.com', '51.la',
    // 免费二级域名/静态托管：多为一次性部署与统计页，实测无可用站点
    'eu.org', 'is-an.org', 'qzz.io', 'xbox.work',
  };

  /// 按前缀屏蔽（统计/预览类子域名，如 umami.zwei.de.eu.org）
  static const Set<String> _blockedPrefixes = {
    'umami.', 'matomo.', 'plausible.', 'analytics.', 'tracker.',
    'stats.', 'stat.',
  };

  /// 不是站点后缀的“伪 TLD”（`api.php`、`index.html` 这类误命中）
  static const Set<String> _badTlds = {
    'php', 'html', 'htm', 'js', 'css', 'json', 'md', 'txt', 'xml', 'png',
    'jpg', 'jpeg', 'gif', 'webp', 'svg', 'ico', 'pdf', 'mp4', 'apk', 'zip',
    'rar', '7z', 'exe', 'dll', 'bat', 'sh', 'yml', 'yaml', 'ini', 'log',
  };

  static String _trimTail(String s) =>
      s.replaceAll(RegExp(r'''[.,;:!?)\]}'"]+$'''), '');

  static String? _base64UrlDecode(String input) {
    var b = input
        .replaceAll('-', '+')
        .replaceAll('_', '/')
        .replaceAll(' ', '+');
    while (b.length % 4 != 0) {
      b += '=';
    }
    try {
      final out = utf8.decode(base64.decode(b));
      return out.startsWith('http') ? out : null;
    } catch (_) {
      return null;
    }
  }

  static String? _firstText(Map<dynamic, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k]?.toString().trim();
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  // ==================== HTTP ====================

  static Future<String?> _fetch(String url, {bool github = false, bool raw = false}) {
    final override = debugFetchText;
    if (override != null) return override(url);
    return _fetchRemote(url, github: github, raw: raw);
  }

  static Future<String?> _fetchRemote(
      String url, {bool github = false, bool raw = false}) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: _fetchTimeout,
      responseType: ResponseType.plain,
      validateStatus: (code) => code != null && code < 500,
      headers: {
        'user-agent': github ? 'jianju-discovery' : ApiConstants.browserUserAgent,
        'accept': raw
            ? 'application/vnd.github.raw'
            : github
                ? 'application/vnd.github+json'
                : 'text/html,application/xhtml+xml,application/xml;q=0.9,'
                    '*/*;q=0.8',
        'accept-language': 'zh-CN,zh;q=0.9',
      },
    ));
    try {
      final resp = await dio.get<dynamic>(url);
      final code = resp.statusCode ?? 0;
      if (code >= 400) return null;
      final body = resp.data?.toString() ?? '';
      return body.isEmpty ? null : body;
    } catch (_) {
      return null;
    } finally {
      dio.close(force: true);
    }
  }

  static String _message(Object e) {
    final s = e.toString();
    const prefix = 'Exception: ';
    final body = s.startsWith(prefix) ? s.substring(prefix.length) : s;
    return body.trim().isEmpty ? '未知错误' : body.trim();
  }
}
