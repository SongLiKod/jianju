import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/episode.dart';
import 'api_service.dart';

/// 跨集预缓存（"缓冲大小"设置的第二用途）
///
/// 缓冲预算不再只服务当前集：
///  - 当前集：mpv `cache-secs` 网络读取余量（原有能力）
///  - 后续集：按同一预算把下一集、下下集……顺序下载到本地，
///    换集时直接从本地文件起播——跳过直链解析与网络首缓冲，
///    黑屏从数秒降到毫秒级，且天然免疫 CDN 中途掐线
///
/// 源站直链为 HLS（master→variant 清单→.ts 分片）：逐片下载后按
/// 清单顺序拼成单个 MPEG-TS 文件（拼接合法，mpv 直接可播可 seek）。
///
/// 预算换算按实测平均码率约 4.8Mbps（600KB/s，含 10Mbps 中插贴片）：
///  - 5 分钟 ≈ 180MB ≈ 2~3 集；1 分钟 ≈ 36MB 至少保一集（单集 2 倍容差）
///  - 总占用上限 500MB；单集下载优先，后续集受总预算控制（LRU 淘汰）
/// 文件存放在系统临时目录，存储紧张时系统可回收。
class PrebufferService {
  PrebufferService._();

  /// 预算换算码率（字节/秒，按含中插贴片的实测平均值）
  static const int bytesPerSec = 600 * 1024;

  /// 小于该预算不做跨集预缓存（默认 20s 保持原行为）
  static const int minBudgetSecs = 60;

  /// 总预算硬上限（防自定义超大值吃满磁盘）
  static const int maxBudgetBytes = 500 * 1024 * 1024;

  /// 单次链路最多前瞻的集数
  static const int maxLookAhead = 8;

  /// 分块间小睡：限速约 1~2MB/s，避免与当前集播放争带宽
  static const Duration _chunkDelay = Duration(milliseconds: 10);

  /// 小于该大小视为无效缓存（防下载到错误页/播放列表被当成本地视频）
  static const int minValidBytes = 1024 * 1024;

  /// 缓存格式版本：升级时清空旧缓存（v2=已剔除插播广告段）
  static const int cacheVersion = 2;

  static bool _running = false;

  static int budgetBytes(int bufferSecs) {
    final cap = bufferSecs * bytesPerSec;
    return cap > maxBudgetBytes ? maxBudgetBytes : cap;
  }

  static Future<Directory> _dir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/prebuffer');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _fileFor(String bookId, int index,
      [String ext = 'ts']) async {
    final dir = await _dir();
    return File('${dir.path}/${bookId}_$index.$ext');
  }

  /// 该集的本地缓存路径（文件完整且够大才返回；下载中只有 .part 不算）
  static Future<String?> localPathFor(String bookId, int index) async {
    try {
      for (final ext in const ['ts', 'mp4']) {
        final file = await _fileFor(bookId, index, ext);
        if (!await file.exists()) continue;
        final len = await file.length();
        if (len >= minValidBytes) return file.path;
        if (len > 0) {
          debugPrint('[PBF] 第$index集缓存无效（$len B），删除');
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return null;
  }

  /// 预缓存已占字节
  static Future<int> totalBytes() async {
    try {
      final dir = await _dir();
      var total = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          if (entity.uri.pathSegments.last.startsWith('.')) continue; // .v 等标记
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// LRU 淘汰：超出预算时从最旧文件开始删（含失败残留的 .part）
  static Future<void> _evictTo(int capBytes) async {
    try {
      final dir = await _dir();
      final files = <File>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File &&
            !entity.uri.pathSegments.last.startsWith('.')) {
          files.add(entity);
        }
      }
      if (files.isEmpty) return;
      files.sort((a, b) {
        final ta = a.lastModifiedSync();
        final tb = b.lastModifiedSync();
        return ta.compareTo(tb);
      });
      var total = 0;
      for (final f in files) {
        try {
          total += await f.length();
        } catch (_) {}
      }
      for (final f in files) {
        if (total <= capBytes) break;
        try {
          final len = await f.length();
          await f.delete();
          total -= len;
          debugPrint('[PBF] 超预算，淘汰 ${f.uri.pathSegments.last}'
              ' (${_Fmt.mb(len)})');
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 缓存版本检查：格式升级后旧文件作废（旧缓存含插播广告段）
  static Future<void> _ensureVersion() async {
    try {
      final dir = await _dir();
      final v = File('${dir.path}/.v');
      final cur =
          await v.exists() ? int.tryParse(await v.readAsString()) ?? 0 : 0;
      if (cur == cacheVersion) return;
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
      await v.writeAsString('$cacheVersion');
      debugPrint('[PBF] 缓存版本升级 -> v$cacheVersion，旧缓存已清空');
    } catch (_) {}
  }

  /// 从 [fromIndex] 之后的第一集起顺序预缓存，直到预算用尽或链路中断。
  /// 全局单飞：同一时间只跑一条链；失败即停（多半是网络问题），
  /// 由播放器在换集/临近结尾时再次触发补跑。
  static Future<void> prefetchChain({
    required String bookId,
    required String title,
    required List<Episode> episodes,
    required int fromIndex,
    required int bufferSecs,
  }) async {
    if (_running) return;
    if (bufferSecs < minBudgetSecs) return;
    _running = true;
    try {
      await _ensureVersion();
      final cap = budgetBytes(bufferSecs);
      await _evictTo(cap);
      final ahead = episodes
          .where((e) => e.index > fromIndex && e.playable)
          .toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      debugPrint('[PBF] 预缓存链启动：第$fromIndex 之后，'
          '预算 ${bufferSecs}s≈${_Fmt.mb(cap)}，'
          '前瞻 ${ahead.length} 集');
      var downloaded = 0;
      for (final ep in ahead) {
        if (downloaded >= maxLookAhead) break;
        if (await localPathFor(bookId, ep.index) != null) continue;
        if (await totalBytes() >= cap) {
          debugPrint('[PBF] 预算用尽，暂停预缓存');
          break;
        }
        try {
          final url = await ApiService.fetchPlayUrl(
            seriesId: bookId,
            vid: ep.itemId,
            title: title,
            episodeIndex: ep.index,
          );
          final u = Uri.parse(url);
          debugPrint('[PBF] 第${ep.index}集直链 ${u.host}${u.path}');
          await _download(url, bookId, ep.index, cap);
          downloaded++;
        } catch (e) {
          debugPrint('[PBF] 第${ep.index}集预缓存失败: $e');
          break;
        }
      }
      debugPrint('[PBF] 预缓存链结束（新下载 $downloaded 集）');
    } finally {
      _running = false;
    }
  }

  /// 下载直链到本地：HLS 清单走分片拼接，其余按整文件下载
  static Future<void> _download(
      String url, String bookId, int index, int cap) async {
    final u = Uri.parse(url);
    if (u.path.toLowerCase().endsWith('.m3u8')) {
      await _downloadHls(url, bookId, index, cap);
      return;
    }
    await _downloadDirect(url, bookId, index, cap);
  }

  /// HLS：拉清单（master 需再取一级 variant）→ 逐片下载按序拼成 .ts。
  /// 分片小而独立，CDN 单连接掐线只影响单片（段内重试 3 次即可），
  /// 整集比单连接下完更稳
  static Future<void> _downloadHls(
      String url, String bookId, int index, int cap) async {
    final file = await _fileFor(bookId, index, 'ts');
    final part = File('${file.path}.part');
    if (await part.exists()) {
      try {
        await part.delete();
      } catch (_) {}
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;
    try {
      var listUrl = url;
      var body = '';
      for (var hop = 0; hop < 3; hop++) {
        body = await _fetchText(listUrl, client);
        final variant = _firstVariant(body);
        if (variant == null) break;
        listUrl = Uri.parse(listUrl).resolve(variant).toString();
        debugPrint('[PBF] variant -> ${Uri.parse(listUrl).path}');
      }
      if (!body.contains('#EXT-X-ENDLIST')) {
        throw Exception('清单非完整点播（无 ENDLIST）');
      }
      if (RegExp(r'#EXT-X-KEY:METHOD=(?!NONE)', caseSensitive: false)
          .hasMatch(body)) {
        throw Exception('清单含加密分片，暂不支持');
      }
      // 按 #EXT-X-DISCONTINUITY 分块；目录（origin+路径）与首块不同的
      // 非首块 = 中插贴片广告（如 khKm9Z55/10110kb），合并时剔除
      final chunks = <List<String>>[];
      var current = <String>[];
      for (final raw in body.split('\n')) {
        final l = raw.trim();
        if (l.isEmpty) continue;
        if (l.startsWith('#')) {
          if (l.toUpperCase().startsWith('#EXT-X-DISCONTINUITY') &&
              current.isNotEmpty) {
            chunks.add(current);
            current = <String>[];
          }
          continue;
        }
        current.add(l);
      }
      if (current.isNotEmpty) chunks.add(current);
      if (chunks.isEmpty) throw Exception('清单无分片');
      String dirOf(String seg) {
        final u = Uri.parse(listUrl).resolve(seg);
        final p = u.path;
        return '${u.origin}${p.substring(0, p.lastIndexOf('/') + 1)}';
      }

      final firstDir = dirOf(chunks.first.first);
      final segs = <String>[];
      var removed = 0;
      for (var ci = 0; ci < chunks.length; ci++) {
        final chunk = chunks[ci];
        if (ci > 0 && dirOf(chunk.first) != firstDir) {
          removed += chunk.length;
          continue;
        }
        segs.addAll(chunk);
      }
      if (removed > 0) {
        debugPrint('[PBF] 第$index集合并时剔除插播广告 $removed 片');
      }
      debugPrint('[PBF] 第$index集 HLS 共 ${segs.length} 片'
          '${removed > 0 ? '（原 ${segs.length + removed}）' : ''}');
      sink = part.openWrite();
      var written = 0;
      // 单集上限：给 2 倍预算容差，保证预算档位至少能完整缓存住一集
      final singleCap =
          cap * 2 > 200 * 1024 * 1024 ? 200 * 1024 * 1024 : cap * 2;
      final base = Uri.parse(listUrl);
      for (var i = 0; i < segs.length; i++) {
        final segUrl = base.resolve(segs[i]).toString();
        final bytes = await _fetchBytes(segUrl, client);
        if (written + bytes.length > singleCap) {
          throw Exception('单集超出预算 ${_Fmt.mb(singleCap)}');
        }
        sink.add(bytes);
        written += bytes.length;
        if (i % 10 == 9) {
          debugPrint('[PBF] 第$index集分片 ${i + 1}/${segs.length} '
              '${_Fmt.mb(written)}');
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (written < minValidBytes) throw Exception('内容过小 ${written}B');
      await part.rename(file.path);
      await _evictTo(cap);
      if (!await file.exists()) throw Exception('写入后被预算淘汰');
      debugPrint('[PBF] 已缓存 第$index集（HLS ${segs.length} 片）'
          ' ${_Fmt.mb(written)}');
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      client.close(force: true);
    }
  }

  /// master 清单里的第一个变体路径
  static String? _firstVariant(String body) {
    if (!body.contains('#EXT-X-STREAM-INF')) return null;
    for (final raw in body.split('\n')) {
      final l = raw.trim();
      if (l.isEmpty || l.startsWith('#')) continue;
      return l;
    }
    return null;
  }

  static Future<String> _fetchText(String url, HttpClient client) async {
    Object? last;
    for (var t = 0; t < 3; t++) {
      try {
        final req = await client.getUrl(Uri.parse(url));
        req.headers.set(
            HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 12)');
        final resp = await req.close().timeout(const Duration(seconds: 20));
        if (resp.statusCode != HttpStatus.ok) {
          throw HttpException('HTTP ${resp.statusCode}');
        }
        final sb = StringBuffer();
        await for (final c in resp) {
          sb.write(utf8.decode(c, allowMalformed: true));
        }
        return sb.toString();
      } catch (e) {
        last = e;
        if (t < 2) await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    throw last ?? Exception('清单下载失败');
  }

  static Future<List<int>> _fetchBytes(String url, HttpClient client) async {
    Object? last;
    for (var t = 0; t < 5; t++) {
      try {
        final builder = BytesBuilder(copy: false);
        var got = 0;
        // 该 CDN 对中插贴片等资源无条件回 206（但 Content-Range 常为全量），
        // 故接受 200/206；206 未拉齐时带 Range 从 got 处续拉
        for (var round = 0; round < 8; round++) {
          final req = await client.getUrl(Uri.parse(url));
          req.headers.set(
              HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 12)');
          if (got > 0) {
            req.headers.set(HttpHeaders.rangeHeader, 'bytes=$got-');
          }
          final resp = await req.close().timeout(const Duration(seconds: 25));
          final sc = resp.statusCode;
          if (sc != HttpStatus.ok && sc != HttpStatus.partialContent) {
            throw HttpException('HTTP $sc');
          }
          if (sc == HttpStatus.ok && got > 0) {
            throw Exception('续传中收到 200，重试本片');
          }
          var total = -1;
          if (sc == HttpStatus.partialContent) {
            final cr = resp.headers.value(HttpHeaders.contentRangeHeader);
            final m = cr == null
                ? null
                : RegExp(r'^bytes\s+\d+-\d+/(\d+)$').firstMatch(cr.trim());
            if (m == null) throw Exception('206 无完整 Content-Range: $cr');
            total = int.parse(m.group(1)!);
          }
          await for (final c in resp) {
            builder.add(c);
            got += c.length;
            await Future<void>.delayed(_chunkDelay);
          }
          if (total < 0 || got >= total) break; // 全量已到手
          if (got == 0) throw Exception('空响应');
        }
        final bytes = builder.takeBytes();
        if (bytes.isEmpty) throw Exception('空分片');
        return bytes;
      } catch (e) {
        last = e;
        debugPrint('[PBF] 分片失败(第${t + 1}次) $url → $e');
        if (t < 4) await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    throw last ?? Exception('分片下载失败');
  }

  static Future<void> _downloadDirect(
      String url, String bookId, int index, int cap) async {
    final file = await _fileFor(bookId, index, 'mp4');
    final part = File('${file.path}.part');
    if (await part.exists()) {
      // 上次中断的半截：短视频重下更快，不做断点续传
      try {
        await part.delete();
      } catch (_) {}
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers
          .set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 12)');
      req.followRedirects = true;
      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.statusCode != HttpStatus.ok) {
        debugPrint('[PBF] 响应 ${resp.statusCode}'
            ' location=${resp.headers.value(HttpHeaders.locationHeader) ?? "-"}');
        throw HttpException('HTTP ${resp.statusCode}');
      }
      final declared = resp.headers.contentLength;
      if (declared > 0 && declared > cap) {
        throw Exception('单集 ${(declared / 1048576).toStringAsFixed(1)}MB '
            '超出缓冲预算 ${_Fmt.mb(cap)}');
      }
      sink = part.openWrite();
      var written = 0;
      String? head;
      await for (final chunk in resp) {
        sink.add(chunk);
        written += chunk.length;
        head ??= utf8.decode(
            chunk.sublist(0, chunk.length > 160 ? 160 : chunk.length),
            allowMalformed: true);
        if (written > cap) {
          throw Exception('下载超出缓冲预算 ${_Fmt.mb(cap)}');
        }
        await Future<void>.delayed(_chunkDelay);
      }
      debugPrint('[PBF] 响应 #${resp.statusCode} '
          'type=${resp.headers.contentType?.mimeType ?? "-"} '
          'declared=${resp.headers.contentLength} written=$written');
      debugPrint('[PBF] 正文头: ${head ?? "-"}');
      await sink.flush();
      await sink.close();
      sink = null;
      if (written <= 0) throw Exception('空响应');
      await part.rename(file.path);
      await _evictTo(cap);
      if (!await file.exists()) {
        throw Exception('写入后被预算淘汰');
      }
      debugPrint('[PBF] 已缓存 第$index集 ${_Fmt.mb(written)}');
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      client.close(force: true);
    }
  }

  /// 清空跨集预缓存
  static Future<void> clear() async {
    try {
      final dir = await _dir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}

/// 内部格式化（避免依赖 CacheService 引入 flutter_cache_manager）
class _Fmt {
  _Fmt._();

  static String mb(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
