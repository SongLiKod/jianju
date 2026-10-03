import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/constants/app_constants.dart';
import 'package:jianju/core/services/maccms_source.dart';
import 'package:jianju/core/services/play_lines.dart';
import 'package:jianju/core/services/settings_service.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 整站数据源离线测试：数据源 id 编解码 / 条目与分集映射 /
/// vod_play_url 取直链 / 搜索关键词回退
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  group('数据源 id', () {
    test('line: 前缀编解码', () {
      final id = AppConstants.dataSourceOfLine('bsvod.com');
      expect(id, 'line:bsvod.com');
      expect(AppConstants.dataSourceLineId(id), 'bsvod.com');
      expect(AppConstants.dataSourceLineId(AppConstants.dataSourceWeb), '');
    });

    test('剧目/分集 ID 内嵌线路并可还原数据源', () {
      const bookId = 'mg:bsvod.com:123';
      const epId = 'mg:bsvod.com:123:0:12';
      expect(MaccmsSource.hasPrefix(bookId), isTrue);
      expect(MaccmsSource.hasPrefix(epId), isTrue);
      expect(MaccmsSource.hasPrefix('a52:123'), isFalse);
      expect(MaccmsSource.hasPrefix('123'), isFalse);
      expect(MaccmsSource.byId(bookId)?.line.id, 'bsvod.com');
      expect(MaccmsSource.byId(epId)?.line.id, 'bsvod.com');
      expect(MaccmsSource.byId('a52:123'), isNull);
      expect(MaccmsSource.byId('123'), isNull);
    });

    test('仅 API 模式线路可作整站源', () {
      expect(MaccmsSource.fromLineId('bsvod.com'), isNotNull);
      expect(MaccmsSource.fromLineId('thjzsj.cn'), isNull); // html 模式
      expect(MaccmsSource.fromLineId(''), isNull);
      expect(MaccmsSource.fromLineId('not-a-line.com'), isNull);
    });

    test('未设置 line 数据源时 current() 为 null', () {
      expect(MaccmsSource.current(), isNull);
    });

    test('设置 line 数据源后 current() 返回对应站点', () async {
      await SettingsService.setDataSource(
          AppConstants.dataSourceOfLine('bsvod.com'));
      expect(MaccmsSource.current()?.line.id, 'bsvod.com');
      // 非法线路回落 null
      await SettingsService.setDataSource(
          AppConstants.dataSourceOfLine('nope.com'));
      expect(MaccmsSource.current(), isNull);
    });
  });

  group('条目/分集映射', () {
    final item = <String, dynamic>{
      'vod_id': 77,
      'vod_name': '二嫁有喜',
      'vod_pic': 'https://cdn.x.com/cover.jpg',
      'vod_blurb': '<p>她重启人生，<b>再嫁良人</b>。</p>',
      'vod_area': '内地',
      'vod_year': '2025',
      'vod_hits': '125860',
      'vod_score': '9.2',
      'vod_remarks': '全77集',
      'type_name': '短剧',
      'type_id': 5,
      'vod_play_url':
          '第1集\$https://a.x.com/1.m3u8#第2集\$https://a.x.com/2.m3u8'
              r'$$$第1集$https://b.x.com/1.m3u8',
    };

    test('toDrama 映射字段与前缀', () {
      final d = MaccmsSource.toDrama(item, 'bsvod.com')!;
      expect(d.bookId, 'mg:bsvod.com:77');
      expect(d.title, '二嫁有喜');
      expect(d.coverUrl, 'https://cdn.x.com/cover.jpg');
      expect(d.abstractText.contains('她重启人生'), isTrue);
      expect(d.abstractText.contains('<'), isFalse);
      expect(d.tags, ['内地', '2025']);
      expect(d.episodeCount, 2);
      expect(d.readCountText, '12.6万热度');
      expect(d.scoreText, '评分9.2');
      expect(d.statusText, '全77集');
      expect(d.categoryText, '短剧');
    });

    test('toDrama 缺关键字段返回 null', () {
      expect(MaccmsSource.toDrama({'vod_name': 'x'}, 'bsvod.com'), isNull);
      expect(MaccmsSource.toDrama({'vod_id': 1}, 'bsvod.com'), isNull);
    });

    test('episodesOf 取首组播放源并编号', () {
      final eps = MaccmsSource.episodesOf(item, 'bsvod.com');
      expect(eps.length, 2);
      expect(eps.first.itemId, 'mg:bsvod.com:77:0:1');
      expect(eps.last.itemId, 'mg:bsvod.com:77:0:2');
      expect(eps.first.title, '第1集');
      expect(eps.first.index, 1);
      expect(eps.last.index, 2);
      expect(eps.every((e) => e.playable), isTrue);
    });

    test('episodesOf 条目无播放串时为空', () {
      expect(
          MaccmsSource.episodesOf({'vod_id': 1, 'vod_name': 'x'}, 'bsvod.com'),
          isEmpty);
    });
  });

  group('vod_play_url 取直链 urlOfEpisode', () {
    const group = '第1集\$https://a.x.com/1.m3u8#第2集\$https://a.x.com/2.m3u8';

    test('按集序号取对应地址', () {
      expect(MaccmsSource.urlOfEpisode(group, 1),
          'https://a.x.com/1.m3u8');
      expect(MaccmsSource.urlOfEpisode(group, 2),
          'https://a.x.com/2.m3u8');
    });

    test('越界/无地址返回 null', () {
      expect(MaccmsSource.urlOfEpisode(group, 3), isNull);
      expect(MaccmsSource.urlOfEpisode(group, 0), isNull);
      expect(MaccmsSource.urlOfEpisode('第1集\$', 1), isNull);
      expect(MaccmsSource.urlOfEpisode('', 1), isNull);
    });

    test('转义斜杠与裸 URL 均可解析', () {
      expect(MaccmsSource.urlOfEpisode(r'e\$https:\/\/a.x.com\/1.m3u8', 1),
          'https://a.x.com/1.m3u8');
      expect(MaccmsSource.urlOfEpisode('https://a.x.com/1.m3u8', 1),
          'https://a.x.com/1.m3u8');
    });
  });

  group('搜索关键词回退', () {
    test('含空格/标点站名给出可命中的回退词', () {
      final kws = PlayLineResolver.searchKeywords('万妖图录传 第十三季');
      expect(kws, isNotEmpty);
      expect(kws.first, '万妖图录传 第十三季');
      expect(kws.any((k) => !k.contains(' ')), isTrue);
      expect(kws.toSet().length, kws.length);
      expect(kws.every((k) => k.length >= 2), isTrue);
    });

    test('半角标点站名去标点后仍可搜索', () {
      final kws = PlayLineResolver.searchKeywords('重生!丑小鸭逆袭成了万人迷');
      expect(kws.any((k) => !k.contains('!')), isTrue);
    });
  });
}
