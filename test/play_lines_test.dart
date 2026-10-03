import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/constants/app_constants.dart';
import 'package:jianju/core/services/play_lines.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内置线路离线测试：注册表 / 播放页取链 / vod_play_url 解析 / 标题匹配 / 测速排序
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    PlayLineResolver.clearCaches();
  });

  group('线路注册表', () {
    test('至少 20 条且 id 唯一', () {
      expect(kPlayLines.length, greaterThanOrEqualTo(20));
      expect(kPlayLines.map((l) => l.id).toSet().length, kPlayLines.length);
    });

    test('均为 https 基址且双适配模式齐备', () {
      for (final l in kPlayLines) {
        expect(l.base, startsWith('https://'), reason: l.id);
        expect(l.name, isNotEmpty, reason: l.id);
      }
      expect(kPlayLines.where((l) => l.mode == PlayLineMode.api).length,
          greaterThanOrEqualTo(10));
      expect(kPlayLines.where((l) => l.mode == PlayLineMode.html).length,
          greaterThanOrEqualTo(8));
    });

    test('byId 命中注册表', () {
      expect(PlayLineResolver.byId(kPlayLines.first.id), isNotNull);
      expect(PlayLineResolver.byId('not-a-line.com'), isNull);
    });
  });

  group('播放页取链 extractPlayUrl', () {
    test('player_aaaa 含嵌套对象且结尾无分号', () {
      const html = '<html><script>\n'
          'var player_aaaa={"code":1,'
          '"url":"https:\\/\\/cdn.x.com\\/hls\\/index.m3u8",'
          '"vod_data":{"cover":"https://cdn.x.com/a.jpg",'
          '"note":"close } brace"}}\n'
          '</script></html>';
      expect(PlayLineResolver.extractPlayUrl(html),
          'https://cdn.x.com/hls/index.m3u8');
    });

    test('json 内无 m3u8 时兜底页面 m3u8 直链', () {
      const html = 'var player_aaaa={"url":"https://cdn.x.com/logo.jpg",'
          '"vod_data":{"url":"https://cdn.x.com/b.jpg"}};'
          '<i>https://v.x.com/e.m3u8</i>';
      expect(PlayLineResolver.extractPlayUrl(html),
          'https://v.x.com/e.m3u8');
    });

    test('json 有 mp4 直链且页面无 m3u8 时返回该直链', () {
      const html = 'var player_aaaa={"url":"https://v.x.com/ep3.mp4",'
          '"id":"1"};';
      expect(PlayLineResolver.extractPlayUrl(html),
          'https://v.x.com/ep3.mp4');
    });

    test('url 字段直接是 m3u8 时返回该字段', () {
      const html = 'var player_aaaa={"url":"https://v.x.com/ep3.m3u8",'
          '"id":"1"};';
      expect(PlayLineResolver.extractPlayUrl(html),
          'https://v.x.com/ep3.m3u8');
    });

    test('无 player_aaaa 时兜底页面 m3u8 直链', () {
      const html = '<div>播放地址："https://cdn.x.com/hls/ep.m3u8?t=1"</div>';
      expect(PlayLineResolver.extractPlayUrl(html),
          'https://cdn.x.com/hls/ep.m3u8?t=1');
    });

    test('完全没有可播地址时返回 null', () {
      const html = '<html><body>404 not found</body></html>';
      expect(PlayLineResolver.extractPlayUrl(html), isNull);
    });
  });

  group('vod_play_url 解析 episodeFromPlayUrl', () {
    const vod = r'线路1$https:\/\/a.com\/1.m3u8'
        r'#https:\/\/a.com\/2.m3u8'
        r'#https:\/\/a.com\/3.m3u8'
        r'$$$线路2$https:\/\/b.com\/1.m3u8';

    test('按集号取首条线路的集', () {
      expect(PlayLineResolver.episodeFromPlayUrl(vod, 1),
          'https://a.com/1.m3u8');
      expect(PlayLineResolver.episodeFromPlayUrl(vod, 2),
          'https://a.com/2.m3u8');
      expect(PlayLineResolver.episodeFromPlayUrl(vod, 3),
          'https://a.com/3.m3u8');
    });

    test('超出集数返回 null', () {
      expect(PlayLineResolver.episodeFromPlayUrl(vod, 4), isNull);
      expect(PlayLineResolver.episodeFromPlayUrl(vod, 0), isNull);
      expect(PlayLineResolver.episodeFromPlayUrl(null, 1), isNull);
      expect(PlayLineResolver.episodeFromPlayUrl('', 1), isNull);
    });

    test('首条线路集数不足时回落第二条线路', () {
      const short = r'短$https://s.com/1.m3u8'
          r'$$$长$https://l.com/1.m3u8#https://l.com/2.m3u8';
      expect(PlayLineResolver.episodeFromPlayUrl(short, 2),
          'https://l.com/2.m3u8');
    });
  });

  group('标题匹配 nameMatches', () {
    test('完全一致', () {
      expect(PlayLineResolver.nameMatches('宴律，你的白月光回国了',
          '宴律，你的白月光回国了'), isTrue);
    });

    test('站点名带后缀也算命中', () {
      expect(
          PlayLineResolver.nameMatches('宴律，你的白月光回国了 全集在线观看',
              '宴律，你的白月光回国了'),
          isTrue);
      // 较短站点名允许包含匹配，但至少 4 字（防短词误配）
      expect(
          PlayLineResolver.nameMatches('万妖图录传', '万妖图录传 第十三季'),
          isTrue);
      expect(PlayLineResolver.nameMatches('宴律', '宴律，你的白月光回国了'),
          isFalse);
    });

    test('不同剧不命中', () {
      expect(PlayLineResolver.nameMatches('天剑', '宴律'), isFalse);
      expect(PlayLineResolver.nameMatches('', '宴律'), isFalse);
      expect(PlayLineResolver.nameMatches('宴律', ''), isFalse);
    });
  });

  group('测速排序 orderedLines', () {
    test('EMA 快者优先、连续失败惩罚、未测速居中', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.keyPlayLineStats: jsonEncode({
          'bsvod.com': {'ema': 1500.0, 'fail': 0},
          'zmvod.com': {'ema': 9000.0, 'fail': 0},
          'chvod.com': {'ema': 800.0, 'fail': 3},
        }),
      });
      await StorageService.init();
      PlayLineResolver.clearCaches();

      final ordered = PlayLineResolver.orderedLines();
      // 1500 最快
      expect(ordered.first.id, 'bsvod.com');
      // 连续失败 3 次：800 + 3*1500 = 5300，仍优于未测速（6000）
      final chvodIndex =
          ordered.indexWhere((l) => l.id == 'chvod.com');
      final unknownIndex =
          ordered.indexWhere((l) => l.id == 'thjzsj.cn');
      expect(chvodIndex, lessThan(unknownIndex));
      // 慢线（9000）排在未测速之后，垫底
      expect(ordered.last.id, 'zmvod.com');
      expect(ordered.length, kPlayLines.length);
    });

    test('statOf 读出持久化样本', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.keyPlayLineStats: jsonEncode({
          'lvvod.com': {'ema': 2345.5, 'ok': 7, 'fail': 2},
        }),
      });
      await StorageService.init();
      PlayLineResolver.clearCaches();

      final st = PlayLineResolver.statOf('lvvod.com');
      expect(st.emaMs, closeTo(2345.5, 0.01));
      expect(st.ok, 7);
      expect(st.fails, 2);
      expect(PlayLineResolver.statOf('unknown.com').emaMs, isNull);
    });
  });
}
