import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/maccms_source.dart';
import 'package:jianju/core/services/play_headers.dart';
import 'package:jianju/core/services/play_lines.dart';
import 'package:jianju/core/services/prebuffer_service.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 线上诊断：《仙逆》161「Failed to recognize file format」
/// 关键疑问：
///  1) 该流是否 AES 加密（加密分片预缓存会拼出不可播的 .ts）
///  2) 起播清单改写是否会生成「key 相对路径指向本地文件」的坏清单
///  3) 不带 Referer/浏览器 UA 时 CDN 是否返回 HTML
class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

void main() {
  setUp(() async {
    PathProviderPlatform.instance = _FakePathProvider();
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    PlayLineResolver.clearCaches();
  });

  test('probe 仙逆 ep161 清单改写 / 加密 / 防盗链体检', () async {
    final site = MaccmsSource.fromLineId('bsvod.com')!;
    final hits = await site.search('仙逆');
    expect(hits, isNotEmpty);
    final detail = await site.detail(hits.first.bookId);
    final url = await site.playUrl(detail.episodes[160].itemId);
    // ignore: avoid_print
    print('URL $url');

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.bytes,
      validateStatus: (c) => c != null && c < 600,
    ));

    // --- 1) 沿 master → 媒体清单取正文，判断加密/广告分块 ---
    var listUrl = url;
    var body = '';
    for (var hop = 0; hop < 3; hop++) {
      final resp = await dio.get<String>(listUrl,
          options: Options(
              headers: PlayHeaders.forUrl(url),
              responseType: ResponseType.plain));
      body = resp.data ?? '';
      final variant = body
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty && !l.startsWith('#'),
              orElse: () => '');
      if (variant.isEmpty) break;
      listUrl = Uri.parse(listUrl).resolve(variant).toString();
    }
    final segs = body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();
    final keys = RegExp(r'#EXT-X-KEY:[^\r\n]*', caseSensitive: false)
        .allMatches(body)
        .map((m) => m.group(0) ?? '')
        .toList();
    final disc = RegExp(r'#EXT-X-DISCONTINUITY', caseSensitive: false)
        .allMatches(body)
        .length;
    // ignore: avoid_print
    print('MEDIA url=$listUrl segs=${segs.length} discontinuity=$disc '
        'endlist=${body.contains('#EXT-X-ENDLIST')}');
    // ignore: avoid_print
    print('KEY   ${keys.isEmpty ? '（无，明文流）' : keys.join(' | ')}');

    // --- 2) 起播清单改写（本地 .m3u8 是否还能解析出 key/分片） ---
    final local = await PrebufferService.rewritePlaylist(url);
    // ignore: avoid_print
    print('REWRITE local=${local ?? "null（原样起播网络流）"}');
    if (local != null) {
      final text = await File(local).readAsString();
      // ignore: avoid_print
      print('LOCAL-HEAD\n${text.length > 600 ? text.substring(0, 600) : text}');
      // ignore: avoid_print
      print('LOCAL-contains-ENDLIST=${text.contains('#EXT-X-ENDLIST')} '
          'absoluteSeg=${text.contains('https://')}');
      // key 行若仍是根相对路径，mpv 解析 key 会指向 file:///...
      final keyLine = RegExp(r'#EXT-X-KEY:[^\r\n]*').firstMatch(text)?.group(0);
      // ignore: avoid_print
      print('LOCAL-KEY ${keyLine ?? "（无）"}');
    }

    // --- 3) key 直取（验证加密密钥可达性） ---
    final keyMatch =
        RegExp(r'URI="([^"]+)"').firstMatch(keys.isEmpty ? '' : keys.first);
    if (keyMatch != null) {
      final keyUrl = Uri.parse(listUrl).resolve(keyMatch.group(1)!).toString();
      try {
        final r = await dio.get<List<int>>(keyUrl,
            options: Options(headers: PlayHeaders.forUrl(url)));
        // ignore: avoid_print
        print('KEY-FETCH HTTP ${r.statusCode} bytes=${r.data?.length} url=$keyUrl');
      } catch (e) {
        // ignore: avoid_print
        print('KEY-FETCH FAIL $keyUrl -> $e');
      }
    }

    // --- 4) 裸请求（无 UA/Referer，模拟未带请求头的播放器） ---
    final bare = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.bytes,
      validateStatus: (c) => c != null && c < 600,
      headers: {'user-agent': 'mpv/0.38.0'},
    ));
    final r = await bare.get<List<int>>(url);
    final b = r.data ?? const <int>[];
    final head =
        String.fromCharCodes(b.take(120)).replaceAll(RegExp(r'\s+'), ' ');
    // ignore: avoid_print
    print('BARE  HTTP ${r.statusCode} '
        'ct=${r.headers.value(Headers.contentTypeHeader)} bytes=${b.length} '
        'head="$head"');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
