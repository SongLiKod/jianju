import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/constants/app_constants.dart';
import 'package:jianju/core/services/line_quality.dart';
import 'package:jianju/core/services/play_lines.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 清晰度增强（docs/简剧 - 清晰度增强方案.md）
/// 路径 A：master 变体选择 + 首片码率探测 + 按码率选线
void main() {
  // 注意：这里不初始化 TestWidgetsFlutterBinding —— 它会把 HttpClient 全部
  // 拦成 400，probeKbps 的本地回环服务器就打不通了。
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    PlayLineResolver.clearCaches();
    LineQuality.resetForTest();
  });

  tearDown(LineQuality.resetForTest);

  // ==================== master 变体解析 ====================

  group('parseVariants', () {
    const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=469000,RESOLUTION=720x1280
low/index.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=1000000,BANDWIDTH=1500000,RESOLUTION=1080x1920
high/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=720x1280
mid/index.m3u8
''';

    test('按 BANDWIDTH 降序，AVERAGE-BANDWIDTH 不抢占主带宽字段', () {
      final v = LineQuality.parseVariants(master);
      expect(v.length, 3);
      expect(v[0].bandwidth, 1500000);
      expect(v[1].bandwidth, 800000);
      expect(v[2].bandwidth, 469000);
      expect(v[0].uri, 'high/index.m3u8');
      expect(v[0].width, 1080);
      expect(v[0].height, 1920);
      expect(v[0].label, '1080x1920@1500k');
    });

    test('pickBestVariant 取最高档，媒体清单返回 null', () {
      expect(LineQuality.pickBestVariant(master), 'high/index.m3u8');
      expect(
        LineQuality.pickBestVariant(
            '#EXTM3U\n#EXTINF:2.0,\nseg0.ts\n#EXT-X-ENDLIST'),
        isNull,
      );
      expect(LineQuality.pickBestVariant(''), isNull);
    });

    test('变体 URI 支持带注释行与空行的清单', () {
      const messy = '''
#EXTM3U
# 表示
#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=720x1280

  play.m3u8
''';
      expect(LineQuality.pickBestVariant(messy), 'play.m3u8');
    });
  });

  // ==================== 码率探测 ====================

  group('probeKbps', () {
    HttpServer? server;
    final segment = List<int>.generate(250000, (i) => i & 0xff);

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        final path = req.uri.path;
        if (path.endsWith('master.m3u8')) {
          req.response.write('#EXTM3U\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=469000,RESOLUTION=720x1280\n'
              'low.m3u8\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1080x1920\n'
              'high.m3u8\n');
        } else if (path.endsWith('high.m3u8')) {
          req.response.write('#EXTM3U\n'
              '#EXTINF:2.0,\n'
              'seg0.ts\n'
              '#EXT-X-ENDLIST\n');
        } else if (path.endsWith('seg0.ts')) {
          final range = req.headers.value(HttpHeaders.rangeHeader);
          if (range != null) {
            // 只回第 1 个字节，把总长放在 Content-Range 里
            req.response.statusCode = HttpStatus.partialContent;
            req.response.headers
                .set(HttpHeaders.contentRangeHeader, 'bytes 0-0/${segment.length}');
            req.response.headers
                .set(HttpHeaders.contentTypeHeader, 'video/mp2t');
            req.response.add(const [0]);
          } else {
            req.response.add(segment);
          }
        } else {
          req.response.statusCode = HttpStatus.notFound;
        }
        await req.response.close();
      });
    });

    tearDown(() async {
      await server?.close(force: true);
      server = null;
    });

    String url(String p) =>
        'http://127.0.0.1:${server!.port}/$p';

    test('跳到带宽最高档的首片并按 EXTINF 时长算出 kbps', () async {
      // 250000 字节 × 8 ÷ 2.0s ÷ 1000 = 1000 kbps
      final kbps = await LineQuality.probeKbps(url('master.m3u8'));
      expect(kbps, 1000);
    });

    test('直接给媒体清单也能测', () async {
      final kbps = await LineQuality.probeKbps(url('high.m3u8'));
      expect(kbps, 1000);
    });

    test('非 m3u8 / 404 / 无 EXTINF 时长均返回 null', () async {
      expect(await LineQuality.probeKbps(url('seg0.ts')), isNull);
      expect(await LineQuality.probeKbps(url('missing.m3u8')), isNull);
    });
  });

  // ==================== 后台探测闸门 ====================

  group('probeInBackground', () {
    test('同一 URL 去重、并发上限 2、resetForTest 可复位', () {
      const a = 'http://127.0.0.1:1/a.m3u8';
      const b = 'http://127.0.0.1:1/b.m3u8';
      const c = 'http://127.0.0.1:1/c.m3u8';

      expect(LineQuality.probeInBackground(a), isTrue);
      expect(LineQuality.probeInBackground(a), isFalse, reason: '去重');
      expect(LineQuality.probeInBackground(b), isTrue);
      expect(LineQuality.probeInBackground(c), isFalse, reason: '并发上限 2');

      LineQuality.resetForTest();
      expect(LineQuality.probeInBackground(c), isTrue);
      LineQuality.resetForTest();
    });
  });

  // ==================== 清晰度优先选线 ====================

  group('orderedLinesForPlay（路径 A）', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        AppConstants.keyPlayLineStats: jsonEncode({
          'bsvod.com': {'ema': 1500.0, 'fail': 0, AppConstants.statBitrateKey: 469},
          'zmvod.com': {'ema': 9000.0, 'fail': 0, AppConstants.statBitrateKey: 1138},
          'chvod.com': {'ema': 800.0, 'fail': 0, AppConstants.statBitrateKey: 1002},
        }),
      });
      await StorageService.init();
      PlayLineResolver.clearCaches();
    });

    test('statOf 读出码率样本', () {
      expect(PlayLineResolver.statOf('bsvod.com').bitrateKbps, 469);
      expect(PlayLineResolver.statOf('bsvod.com').hasBitrate, isTrue);
      expect(PlayLineResolver.statOf('thjzsj.cn').bitrateKbps, isNull);
      expect(PlayLineResolver.statOf('thjzsj.cn').hasBitrate, isFalse);
    });

    test('开关开：码率高者优先，与耗时排序无关', () {
      final ordered = PlayLineResolver.orderedLinesForPlay();
      expect(ordered.first.id, 'zmvod.com'); // 1138 最高
      expect(ordered[1].id, 'chvod.com'); // 1002
      expect(ordered.last.id, 'bsvod.com'); // 469 垫底（尽管它耗时最快）
      expect(ordered.length, kPlayLines.length);
      // 排序不影响搜索用的旧接口（仍按耗时：chvod 800ms 最快）
      expect(PlayLineResolver.orderedLines().first.id, 'chvod.com');
    });

    test('开关开但码率未知的线路按占位值并列，退回耗时排序', () async {
      // 与既有样本同码率占位（800）的线路之间，应按 EMA 分出先后
      SharedPreferences.setMockInitialValues({
        AppConstants.keyPlayLineStats: jsonEncode({
          'bsvod.com': {'ema': 1500.0, 'fail': 0, AppConstants.statBitrateKey: 800},
          'zmvod.com': {'ema': 9000.0, 'fail': 0, AppConstants.statBitrateKey: 800},
        }),
      });
      await StorageService.init();
      PlayLineResolver.clearCaches();

      final ordered = PlayLineResolver.orderedLinesForPlay();
      expect(ordered.first.id, 'bsvod.com'); // 同码率，比耗时
      expect(ordered.last.id, 'zmvod.com');
    });

    test('连续失败 ≥2 的高码率线路被降级为占位值', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.keyPlayLineStats: jsonEncode({
          'bsvod.com': {'ema': 1500.0, 'fail': 0, AppConstants.statBitrateKey: 469},
          'zmvod.com': {'ema': 9000.0, 'fail': 2, AppConstants.statBitrateKey: 1138},
        }),
      });
      await StorageService.init();
      PlayLineResolver.clearCaches();

      final ordered = PlayLineResolver.orderedLinesForPlay();
      // zmvod 码率 1138 最高但连续失败 2 次 → 降到占位 800，与未知线路并列后按耗时排
      final zi = ordered.indexWhere((l) => l.id == 'zmvod.com');
      final ui = ordered.indexWhere((l) => l.id == 'thjzsj.cn');
      expect(zi, greaterThan(ui));
      // bsvod 是真实 469 → 全场最低，垫底
      expect(ordered.last.id, 'bsvod.com');
    });

    test('开关关：退化为纯耗时排序，行为与旧逻辑一致', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.keyLineQualityFirst: '0', // 设置项按 '1'/'0' 字符串存
        AppConstants.keyPlayLineStats: jsonEncode({
          'bsvod.com': {'ema': 1500.0, 'fail': 0, AppConstants.statBitrateKey: 469},
          'zmvod.com': {'ema': 9000.0, 'fail': 0, AppConstants.statBitrateKey: 1138},
        }),
      });
      await StorageService.init();
      PlayLineResolver.clearCaches();

      final ordered = PlayLineResolver.orderedLinesForPlay();
      expect(ordered.first.id, 'bsvod.com'); // 最快的线路，码率被忽略
      expect(ordered, equals(PlayLineResolver.orderedLines()));
    });
  });
}
