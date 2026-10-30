import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/prebuffer_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 同目录片尾广告块（bhvod 类站点）的识别与剔除
///
/// 症状：《惊悚boss》在安卓上播到 107s 进入片尾贴片（与正片同目录、码率
/// 3238 vs 1138 kbps）→ mpv 把流重启回 00:00 → 同一集无限重播、永不
/// end-of-episode、不跳下一集，重启瞬时音频爆音（系统 asd_pop 实测检出）。
/// 判据：非首 discontinuity 块用 Range 取真实分片大小，码率中位数与首块
/// 偏离 ≥1.8 倍即判广告。
class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

class _Site {
  final HttpServer server;
  final List<String> reqs = <String>[];

  _Site(this.server);

  String get master => 'http://127.0.0.1:${server.port}/hls/index.m3u8';

  Future<void> close() => server.close(force: true);
}

/// 本地假站：4 片正片 + 可选 discontinuity 尾块（2 片），支持 Range；
/// [preRollAd] 时先出 2 片异目录片头广告，块序变成 广告/正片/广告/正片
Future<_Site> _start({
  required int contentLen,
  required int adLen,
  bool adOtherDir = false,
  bool discontinuity = true,
  bool preRollAd = false,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final site = _Site(server);
  final b = StringBuffer()
    ..writeln('#EXTM3U')
    ..writeln('#EXT-X-VERSION:3')
    ..writeln('#EXT-X-TARGETDURATION:4');
  void seg(String url) => b
    ..writeln('#EXTINF:4.0,')
    ..writeln(url);
  void adSegs() {
    for (var i = 0; i < 2; i++) {
      seg(adOtherDir ? '/ad/ad$i.ts' : 'ad$i.ts');
    }
  }

  if (preRollAd) {
    adSegs(); // 片头贴片（独立块，后接 DISCONTINUITY）
    b.writeln('#EXT-X-DISCONTINUITY');
  }
  for (var i = 0; i < 4; i++) {
    seg('c$i.ts');
  }
  if (discontinuity) {
    b.writeln('#EXT-X-DISCONTINUITY');
    adSegs();
    if (preRollAd) {
      b.writeln('#EXT-X-DISCONTINUITY');
      for (var i = 4; i < 8; i++) {
        seg('c$i.ts');
      }
    }
  }
  b.writeln('#EXT-X-ENDLIST');
  final playlist = utf8.encode(b.toString());

  server.listen((req) async {
    site.reqs.add(req.uri.path);
    final path = req.uri.path;
    if (path.endsWith('.m3u8')) {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType =
          ContentType('application', 'x-mpegURL');
      req.response.add(playlist);
    } else {
      final len = path.contains('ad') ? adLen : contentLen;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.startsWith('bytes=0-0')) {
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes 0-0/$len');
        req.response.add(const [1]);
      } else {
        req.response.statusCode = HttpStatus.ok;
        req.response.add(List<int>.filled(len, 2));
      }
    }
    await req.response.close();
  });
  return site;
}

void main() {
  setUp(() {
    PathProviderPlatform.instance = _FakePathProvider();
  });

  test('码率判据阈值（1.8 倍双向）', () {
    // 本剧实测：正片 1138kbps、片尾贴片 3238kbps → 比值 2.85
    expect(PrebufferService.isAdRate(1138, 3238), isTrue);
    expect(PrebufferService.isAdRate(1138, 1138), isFalse);
    expect(PrebufferService.isAdRate(1138, 1000), isFalse);
    expect(PrebufferService.isAdRate(1138, 640), isFalse); // 0.562
    expect(PrebufferService.isAdRate(1138, 600), isTrue); // 0.527
  });

  test('同目录高码率片尾块被剔除（起播改写）', () async {
    final site = await _start(contentLen: 100 * 1024, adLen: 400 * 1024);
    try {
      final local = await PrebufferService.rewritePlaylist(site.master);
      expect(local, isNotNull, reason: '应识别广告并写出本地清单');
      final text = await File(local!).readAsString();
      expect(text, startsWith('#EXTM3U'));
      expect(text, contains('c0.ts'));
      expect(text, contains('c3.ts'));
      expect(text, isNot(contains('ad0.ts')), reason: '广告块应被剔除');
      expect(text, isNot(contains('ad1.ts')));
      expect(text, isNot(contains('#EXT-X-DISCONTINUITY')));
      expect(text, contains('#EXT-X-ENDLIST'));
      expect(text, contains('http://127.0.0.1'), reason: '分片必须转成绝对地址');
    } finally {
      await site.close();
    }
  });

  test('同目录同码率块保留（改写返回 null 原样起播）', () async {
    final site = await _start(contentLen: 100 * 1024, adLen: 100 * 1024);
    try {
      final local = await PrebufferService.rewritePlaylist(site.master);
      expect(local, isNull, reason: '码率一致不判广告，不改写');
      expect(site.reqs.where((p) => p.endsWith('.ts')).length, greaterThan(0),
          reason: '应已对两块分片做过 Range 探测');
    } finally {
      await site.close();
    }
  });

  test('异目录块直接按目录判，零探测请求', () async {
    final site =
        await _start(contentLen: 100 * 1024, adLen: 100 * 1024, adOtherDir: true);
    try {
      final local = await PrebufferService.rewritePlaylist(site.master);
      expect(local, isNotNull);
      final text = await File(local!).readAsString();
      expect(text, isNot(contains('/ad/ad0.ts')));
      expect(site.reqs.length, 1, reason: '目录判据命中后不应再发探测请求');
    } finally {
      await site.close();
    }
  });

  test('片头广告在首块时不能把正片删光（fhapi9 症状回归）', () async {
    // 实测：首块 26.6s 片头广告 + 正片两段共 68 分钟，按「首块=正片」
    // 判据会删掉正片、留下广告 → 只能播放广告，正片播放不了
    final site = await _start(
        contentLen: 100 * 1024, adLen: 400 * 1024, adOtherDir: true, preRollAd: true);
    try {
      final local = await PrebufferService.rewritePlaylist(site.master);
      expect(local, isNotNull, reason: '有广告块应写出改写清单');
      final text = await File(local!).readAsString();
      expect(text, isNot(contains('/ad/ad0.ts')), reason: '片头/中插广告都应剔除');
      expect(text, isNot(contains('/ad/ad1.ts')));
      expect(text, contains('c0.ts'), reason: '第一段正片必须保留');
      expect(text, contains('c7.ts'), reason: '第二段正片必须保留');
      expect(text, contains('#EXT-X-ENDLIST'));
      expect(
          site.reqs.where((p) => p.endsWith('.ts')).length, greaterThan(0),
          reason: '同目录的两段正片会走码率基准比对');
    } finally {
      await site.close();
    }
  });

  test('无 discontinuity 清单：零探测、原样起播', () async {
    final site = await _start(
        contentLen: 100 * 1024, adLen: 100 * 1024, discontinuity: false);
    try {
      final local = await PrebufferService.rewritePlaylist(site.master);
      expect(local, isNull);
      expect(site.reqs.length, 1, reason: '常规清单只应请求清单本身');
    } finally {
      await site.close();
    }
  });
}
