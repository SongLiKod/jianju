import 'dart:convert';
import 'dart:io';

import 'play_headers.dart';

/// 清晰度增强 · 路径 A 的探测与选择（docs/简剧 - 清晰度增强方案.md）
///
/// 负责两件事：
///  1. 解析 HLS master 清单的 `#EXT-X-STREAM-INF`，按 `BANDWIDTH` 选最高档
///     （原逻辑只取清单第一个变体，从不读带宽/分辨率）；
///  2. 探测一条播放直链的首片码率（kbps），供线路「清晰度优先」排序使用。
class LineQuality {
  LineQuality._();

  /// 同时进行的码率探测上限：起播时还要抢带宽，压到 2 条
  static const int _maxConcurrent = 2;

  /// 单次请求超时（探测只取清单与 1 个字节，不该慢）
  static const Duration _timeout = Duration(seconds: 6);

  /// 码率合理区间（kbps）：越界视为探测结果不可信
  static const int _minKbps = 20;
  static const int _maxKbps = 60000;

  static int _inflight = 0;
  static final Set<String> _probing = <String>{};

  // ==================== 变体选择 ====================

  /// 解析 master 清单的全部变体，按 `BANDWIDTH` 降序返回。
  /// 媒体清单（无 `#EXT-X-STREAM-INF`）返回空列表。
  static List<Variant> parseVariants(String master) {
    final out = <Variant>[];
    final lines = master.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final attr = lines[i].trim();
      final up = attr.toUpperCase();
      if (!up.startsWith('#EXT-X-STREAM-INF:')) continue;
      var uri = '';
      for (var j = i + 1; j < lines.length; j++) {
        final n = lines[j].trim();
        if (n.isEmpty || n.startsWith('#')) continue;
        uri = n;
        break;
      }
      if (uri.isEmpty) continue;
      final res = RegExp(r'RESOLUTION=(\d+)x(\d+)', caseSensitive: false)
          .firstMatch(attr);
      out.add(Variant(
        bandwidth: _intOf(attr, 'BANDWIDTH') ?? _intOf(attr, 'AVERAGE-BANDWIDTH') ?? 0,
        width: res == null ? 0 : int.parse(res.group(1)!),
        height: res == null ? 0 : int.parse(res.group(2)!),
        uri: uri,
      ));
    }
    out.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    return out;
  }

  /// 带宽最高的变体 URI；非 master 返回 null
  static String? pickBestVariant(String master) {
    final v = parseVariants(master);
    return v.isEmpty ? null : v.first.uri;
  }

  static int? _intOf(String attr, String key) {
    // 前面必须是逗号/冒号/空白：避免 BANDWIDTH 误匹配 AVERAGE-BANDWIDTH
    final m =
        RegExp('(?:^|[,;:\\s])$key=(\\d+)', caseSensitive: false).firstMatch(attr);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  // ==================== 码率探测 ====================

  /// 探测 [url] 的首片码率（kbps，四舍五入）；任何一步失败返回 null。
  ///
  /// 步骤：拉清单 →（master 则跳到带宽最高的变体）→ 取首片与其 `EXTINF`
  /// 时长 → `Range: bytes=0-0` 取分片总字节 → 字节×8÷时长。
  static Future<int?> probeKbps(
    String url, {
    Map<String, String>? headers,
  }) async {
    if (!url.toLowerCase().contains('.m3u8')) return null;
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final hdr = headers ?? PlayHeaders.forUrl(url);
      var base = url;
      var body = await _text(client, base, hdr);
      if (body == null || body.isEmpty) return null;
      final best = pickBestVariant(body);
      if (best != null) {
        base = Uri.parse(base).resolve(best).toString();
        body = await _text(client, base, hdr);
        if (body == null || body.isEmpty) return null;
      }
      String? seg;
      var dur = 0.0;
      for (final raw in body.split('\n')) {
        final l = raw.trim();
        if (l.isEmpty) continue;
        if (l.toUpperCase().startsWith('#EXTINF:')) {
          dur = double.tryParse(l.substring(8).split(',').first.trim()) ?? 0;
        } else if (!l.startsWith('#')) {
          seg = l;
          break;
        }
      }
      if (seg == null || dur <= 0) return null;
      final total = await _rangeSize(client, Uri.parse(base).resolve(seg).toString(), hdr);
      if (total == null || total <= 0) return null;
      final kbps = (total * 8 / dur / 1000).round();
      if (kbps < _minKbps || kbps > _maxKbps) return null;
      return kbps;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 后台探测：限并发、去重、延迟起跑，结果回调 [onResult]（失败回 null）。
  /// 返回 false 表示本次未发起（已在探测中或已达并发上限），调用方无需重试。
  static bool probeInBackground(
    String url, {
    Map<String, String>? headers,
    void Function(int? kbps)? onResult,
  }) {
    if (_inflight >= _maxConcurrent) return false;
    if (!_probing.add(url)) return false;
    _inflight++;
    // 稍作延迟：把带宽让给起播首缓冲
    Future<void>.delayed(const Duration(milliseconds: 1200), () async {
      int? kbps;
      try {
        kbps = await probeKbps(url, headers: headers);
      } catch (_) {
        kbps = null; // 探测失败不影响播放
      } finally {
        _inflight--;
        _probing.remove(url);
      }
      try {
        onResult?.call(kbps);
      } catch (_) {
        // 回调异常不影响播放
      }
    });
    return true;
  }

  static Future<String?> _text(
      HttpClient client, String url, Map<String, String> hdr) async {
    final req = await client.getUrl(Uri.parse(url));
    for (final e in hdr.entries) {
      req.headers.set(e.key, e.value);
    }
    final resp = await req.close().timeout(_timeout);
    if (resp.statusCode != HttpStatus.ok) return null;
    return await utf8.decoder.bind(resp).join();
  }

  /// `Range: bytes=0-0` 取分片总字节。该类 CDN 对 HEAD 回 502，只能用 Range
  /// 取 `Content-Range` 末尾的 total；CDN 忽略 Range 时退化为 content-length。
  static Future<int?> _rangeSize(
      HttpClient client, String url, Map<String, String> hdr) async {
    final req = await client.getUrl(Uri.parse(url));
    for (final e in hdr.entries) {
      req.headers.set(e.key, e.value);
    }
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    final resp = await req.close().timeout(_timeout);
    int? total;
    if (resp.statusCode == HttpStatus.partialContent) {
      final cr = resp.headers.value(HttpHeaders.contentRangeHeader);
      final m = cr == null ? null : RegExp(r'/(\d+)\s*$').firstMatch(cr.trim());
      if (m != null) total = int.parse(m.group(1)!);
    } else if (resp.statusCode == HttpStatus.ok && resp.contentLength > 0) {
      total = resp.contentLength;
    }
    await resp.drain<void>();
    return total;
  }

  /// 测试辅助：复位并发闸门与去重集合
  static void resetForTest() {
    _inflight = 0;
    _probing.clear();
  }
}

/// master 清单里的一档变体
class Variant {
  final int bandwidth;
  final int width;
  final int height;
  final String uri;

  const Variant({
    required this.bandwidth,
    required this.width,
    required this.height,
    required this.uri,
  });

  /// 供日志/测试展示，如 `1280x720@800k`
  String get label =>
      '${width}x$height@${(bandwidth / 1000).round()}k';
}
