import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../constants/api_constants.dart';
import 'request_throttler.dart';

/// 官方网页源 HTTP 客户端
///
/// - 浏览器 UA + Cookie（启动先 GET 首页种 cookie，否则搜索等页返回空壳）
/// - 请求节流 + 指数退避重试
/// - SSR 数据提取：定位 _ROUTER_DATA，花括号配对截取 JSON
class HttpClient {
  HttpClient._();

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConstants.webBase,
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    responseType: ResponseType.plain,
    followRedirects: true,
    validateStatus: (code) => code != null && code < 500,
    headers: const {
      'user-agent': ApiConstants.browserUserAgent,
      'accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'accept-language': 'zh-CN,zh;q=0.9',
    },
  ));

  static final ListQueue<String> _cookies = ListQueue<String>();
  static bool _cookieReady = false;

  /// 确保已种下 cookie（首次请求前先访问首页）
  static Future<void> _ensureCookie() async {
    if (_cookieReady) return;
    try {
      final response = await _dio.get<dynamic>(ApiConstants.pathHome);
      _storeCookies(response);
      _cookieReady = true;
    } catch (_) {
      // 种 cookie 失败不阻塞后续请求（首页请求本身会再带响应 cookie）
      _cookieReady = true;
    }
  }

  static void _storeCookies(Response<dynamic> response) {
    final setCookies = response.headers['set-cookie'];
    if (setCookies == null || setCookies.isEmpty) return;
    _cookies.clear();
    for (final c in setCookies) {
      final pair = c.split(';').first.trim();
      if (pair.isNotEmpty) _cookies.add(pair);
    }
  }

  /// GET 页面 HTML（已节流、已重试、带 cookie）
  static Future<String> getHtml(String path) async {
    return RequestThrottler.instance.run(() => _getHtmlThrottled(path));
  }

  static Future<String> _getHtmlThrottled(String path) async {
    await _ensureCookie();
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final options = _cookies.isEmpty
            ? null
            : Options(headers: {'cookie': _cookies.join('; ')});
        final response = await _dio.get<dynamic>(path, options: options);
        _storeCookies(response);
        final body = response.data?.toString() ?? '';
        if (body.isNotEmpty) return body;
        lastError = '空响应';
      } catch (e) {
        lastError = e;
      }
      await Future<void>.delayed(Duration(milliseconds: 600 * (1 << attempt)));
    }
    throw Exception('页面请求失败: $lastError');
  }

  /// GET 页面并提取 SSR JSON：_ROUTER_DATA 中的目标 loader 对象
  ///
  /// [loaderKeyPattern] 用于匹配 loaderData 的 key（如 'page'、r'category_\$'）；
  /// 不传则返回整个 loaderData 的第一个对象。
  static Future<Map<String, dynamic>?> getSsrJson(
    String path, {
    String? loaderKeyPattern,
  }) async {
    final html = await getHtml(path);
    final root = extractRouterData(html);
    if (root == null) return null;
    final loaderData = root['loaderData'];
    if (loaderData is! Map) return null;
    _mergeDeferredLoaders(html, root);

    if (loaderKeyPattern != null) {
      final pattern = RegExp(loaderKeyPattern);
      Map<String, dynamic>? matched;
      for (final entry in loaderData.entries) {
        if (pattern.hasMatch(entry.key.toString()) &&
            entry.value is Map<String, dynamic>) {
          // 同一路由可能存在多个 loader，取最后一个匹配的
          matched = entry.value as Map<String, dynamic>;
        }
      }
      return matched;
    }
    // 默认取最后一个 Map loader（页面专属 loader 通常在最后）
    Map<String, dynamic>? last;
    for (final v in loaderData.values) {
      if (v is Map<String, dynamic>) last = v;
    }
    return last;
  }

  /// 从 HTML 中截取 SSR 数据 `_ROUTER_DATA = {...}` 的 JSON
  ///
  /// 兼容两种写法：`window._ROUTER_DATA = {...}` 与裸赋值 `_ROUTER_DATA = {...}`；
  /// 逐个候选跳过非赋值用法（`_ROUTER_DATA.s = ...`、`_ROUTER_DATA={}` 等），
  /// 优先返回带 loaderData 的对象。
  static Map<String, dynamic>? extractRouterData(String html) {
    const marker = '_ROUTER_DATA';
    Map<String, dynamic>? fallback;
    var from = 0;
    while (true) {
      final at = html.indexOf(marker, from);
      if (at < 0) break;
      from = at + marker.length;

      final assign = _skipSpaces(html, at + marker.length);
      if (assign >= html.length || html[assign] != '=') continue;
      final start = _skipSpaces(html, assign + 1);
      if (start >= html.length || html[start] != '{') continue;

      final decoded = _decodeObjectAt(html, start);
      if (decoded == null) continue;
      if (decoded.containsKey('loaderData')) return decoded;
      fallback ??= decoded;
    }
    return fallback;
  }

  static int _skipSpaces(String text, int index) {
    var i = index;
    while (i < text.length &&
        (text[i] == ' ' || text[i] == '\n' || text[i] == '\r' || text[i] == '\t')) {
      i++;
    }
    return i;
  }

  /// 合并 SSR 页面里二次注入的 loader 数据
  ///
  /// 部分分区（如详情页相关推荐）不在 _ROUTER_DATA 主 JSON 里，
  /// 而是通过 `mergeLoaderData` / `r` 脚本的 data-fn-args 注入，
  /// 这里按浏览器同款逻辑把载荷写回 loaderData。
  static void _mergeDeferredLoaders(String html, Map<String, dynamic> root) {
    final loaderData = root['loaderData'];
    if (loaderData is! Map) return;

    void assign(String routeKey, String key, Object? payload) {
      if (payload == null) return;
      final route = loaderData[routeKey];
      if (route is Map) route[key] = payload;
    }

    void forEachArgs(String marker, void Function(List<Object?> args) onArgs) {
      var from = 0;
      while (true) {
        final at = html.indexOf(marker, from);
        if (at < 0) return;
        from = at + marker.length;
        final raw = _readAttribute(html, 'data-fn-args', at);
        if (raw == null) continue;
        final args = _tryDecode(_unescapeHtml(raw));
        if (args is List) onArgs(args);
      }
    }

    // mergeLoaderData(["routeKey", [{key, routerDataFnName, routerDataFnArgs}]])
    forEachArgs('data-fn-name="mergeLoaderData"', (args) {
      if (args.length < 2 || args[1] is! List) return;
      final routeKey = args[0].toString();
      for (final entry in args[1] as List) {
        if (entry is! Map) continue;
        final key = entry['key']?.toString();
        final fnArgs = entry['routerDataFnArgs'];
        // 's' 形态只登记 Promise，载荷由随后的 r 脚本注入
        if (key == null || entry['routerDataFnName']?.toString() == 's') {
          continue;
        }
        if (fnArgs is! List) continue;
        for (final arg in fnArgs) {
          final payload = arg is String ? _tryDecode(arg) : arg;
          if (payload is Map || payload is List) {
            assign(routeKey, key, payload);
            break;
          }
        }
      }
    });

    // r(["routeKey", "key", payload])
    forEachArgs('data-fn-name="r"', (args) {
      if (args.length < 3) return;
      assign(args[0].toString(), args[1].toString(), args[2]);
    });
  }

  /// 读取 [from] 附近的 HTML 属性值（引号包裹，支持前后相邻两种位置）
  static String? _readAttribute(String html, String name, int from) {
    const window = 300;
    var best = -1;
    var bestDist = window + 1;
    final forward = html.indexOf(name, from);
    if (forward >= 0 && forward - from <= window && forward - from < bestDist) {
      best = forward;
      bestDist = forward - from;
    }
    final backward = html.lastIndexOf(name, from);
    if (backward >= 0 && from - backward <= window && from - backward < bestDist) {
      best = backward;
      bestDist = from - backward;
    }
    if (best < 0) return null;

    var i = best + name.length;
    if (i >= html.length || html[i] != '=') return null;
    i++;
    if (i >= html.length) return null;
    final quote = html[i];
    if (quote != '"' && quote != "'") return null;
    i++;
    final end = html.indexOf(quote, i);
    if (end < 0) return null;
    return html.substring(i, end);
  }

  static Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static String _unescapeHtml(String text) => text
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  /// 从 [start] 处的 `{` 开始做花括号配对（字符串状态机），解码单个 JSON 对象
  static Map<String, dynamic>? _decodeObjectAt(String text, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    var end = -1;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          end = i + 1;
          break;
        }
      }
    }
    if (end < 0) return null;
    try {
      final decoded = jsonDecode(text.substring(start, end));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
