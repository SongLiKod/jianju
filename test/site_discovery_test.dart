import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/play_lines.dart';
import 'package:jianju/core/services/site_discovery_service.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在线发现的纯函数契约：链接提取/跳转还原、候选归一化、
/// 搜索结果与友链解析、GitHub 响应解析、订阅 JSON 解析、合并与排序。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    PlayLineResolver.resetCustomLinesForTest();
  });

  // ==================== 链接提取与跳转还原 ====================

  group('extractLinks / absolutize / directUrl', () {
    test('提取双引号与单引号 href，保持出现顺序', () {
      final links = SiteDiscoveryService.extractLinks(
          '<a href="https://a.com/x">1</a>'
          "<a href='https://b.com'>2</a>"
          '<A HREF="https://c.com">3</A>');
      expect(links, ['https://a.com/x', 'https://b.com', 'https://c.com']);
    });

    test('绝对化：协议相对补 https、裸域名补协议、相对/脚本链接丢弃', () {
      expect(SiteDiscoveryService.absolutize('//a.com/x'), 'https://a.com/x');
      expect(SiteDiscoveryService.absolutize('example.com/vod'),
          'https://example.com/vod');
      expect(SiteDiscoveryService.absolutize('https://b.com/'), 'https://b.com/');
      expect(SiteDiscoveryService.absolutize('/relative/path'), isNull);
      expect(SiteDiscoveryService.absolutize('#top'), isNull);
      expect(SiteDiscoveryService.absolutize('javascript:void(0)'), isNull);
      expect(SiteDiscoveryService.absolutize(''), isNull);
    });

    test('DuckDuckGo uddg 跳转还原为真实地址', () {
      final url = SiteDiscoveryService.directUrl(
          'https://duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fvod'
          '&rut=xyz');
      expect(url, 'https://example.com/vod');
    });

    test('Bing ck/a base64 跳转还原为真实地址', () {
      final encoded = base64Url.encode(utf8.encode('https://binged.site/api'));
      final url =
          SiteDiscoveryService.directUrl('https://www.bing.com/ck/a?u=a1$encoded');
      expect(url, 'https://binged.site/api');
    });

    test('解不出的跳转返回 null，非跳转原样返回', () {
      expect(SiteDiscoveryService.directUrl('https://www.bing.com/ck/a?u=a1@@@'),
          isNull);
      expect(
          SiteDiscoveryService.directUrl('https://www.bing.com/ck/a?u=a2zzz'),
          isNull);
      expect(SiteDiscoveryService.directUrl('https://plain.com/x'),
          'https://plain.com/x');
    });
  });

  // ==================== 候选归一化 ====================

  group('candidateBase / normalizeBases', () {
    test('只保留 origin（去路径去查询、小写化）', () {
      expect(SiteDiscoveryService.candidateBase('https://MyVod.com/voddetail/1.html?a=2'),
          'https://myvod.com');
      expect(SiteDiscoveryService.candidateBase('MyVod.com/'), 'https://myvod.com');
      expect(SiteDiscoveryService.candidateBase('http://a-b.com:8080/x'),
          'http://a-b.com:8080');
      expect(SiteDiscoveryService.candidateBase('  https://c.com/  '),
          'https://c.com');
    });

    test('非法地址与无关域名返回 null', () {
      expect(SiteDiscoveryService.candidateBase('/path/x'), isNull);
      expect(SiteDiscoveryService.candidateBase('javascript:void(0)'), isNull);
      expect(SiteDiscoveryService.candidateBase('不是域名'), isNull);
      expect(SiteDiscoveryService.candidateBase('https://duckduckgo.com/x'), isNull);
      expect(SiteDiscoveryService.candidateBase('https://www.bing.com/search'), isNull);
      expect(SiteDiscoveryService.candidateBase('https://github.com/u/r'), isNull);
      expect(SiteDiscoveryService.candidateBase('api.php'), isNull);
      expect(SiteDiscoveryService.candidateBase('index.html'), isNull);
      expect(SiteDiscoveryService.candidateBase('https://beian.miit.gov.cn/'), isNull);
      expect(SiteDiscoveryService.candidateBase('https://school.edu.cn'), isNull);
    });

    test('裸 IP 可作候选（部分接口站直接给 IP）', () {
      expect(SiteDiscoveryService.candidateBase('http://1.2.3.4/vod'),
          'http://1.2.3.4');
    });

    test('按主机去重（www 前缀视为同站，保留首个）', () {
      final out = SiteDiscoveryService.normalizeBases([
        'https://www.a.com/x',
        'http://a.com/y',
        'https://b.com',
        'not-a-domain',
      ]);
      expect(out, ['https://www.a.com', 'https://b.com']);
    });
  });

  // ==================== 搜索结果 / 友链 / GitHub ====================

  group('searchResultBases', () {
    test('解析搜索结果页：还跳转、排引擎自链、去重、丢相对链接', () {
      const html = '''
<html><body>
<a class="r" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample-vod.com%2F&amp;rut=1">站1</a>
<a href="https://www.bing.com/search?q=x">引擎内链</a>
<a href="https://example-vod.com/other">同站另一链接</a>
<a href="/relative/path">相对链接</a>
<a href="https://api.good-vod.net/api.php/provide/vod/">接口</a>
</body></html>''';
      expect(SiteDiscoveryService.searchResultBases(html),
          ['https://example-vod.com', 'https://api.good-vod.net']);
    });

    test('空页面返回空列表', () {
      expect(SiteDiscoveryService.searchResultBases('<html></html>'), isEmpty);
    });

    test('DuckDuckGo 只取结果条目（result__a），忽略页脚导航', () {
      const html = '''
<html><body>
<a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Freal-vod.com%2F">标题</a>
<footer>
  <a href="https://beian.miit.gov.cn/">备案</a>
  <a href="https://duckduckgo.com/about">关于</a>
</footer>
</body></html>''';
      expect(
          SiteDiscoveryService.searchResultBases(html,
              engine: SearchEngine.duckduckgo),
          ['https://real-vod.com']);
    });

    test('Bing 只取 b_algo 结果区，忽略页脚备案链接', () {
      const html = '''
<html><body>
<ol>
<li class="b_algo" data-id="1"><h2><a href="https://first-vod.com/api.php">标题一</a></h2></li>
<li class="b_algo" data-id="2"><h2><a href="https://second-vod.com">标题二</a></h2></li>
</ol>
<footer><a href="https://beian.miit.gov.cn/">京ICP备</a></footer>
</body></html>''';
      expect(
          SiteDiscoveryService.searchResultBases(html, engine: SearchEngine.bing),
          ['https://first-vod.com', 'https://second-vod.com']);
    });

    test('结果区结构识别不出时回退全页解析', () {
      const html = '<a href="https://fallback-vod.com/x">x</a>';
      expect(
          SiteDiscoveryService.searchResultBases(html, engine: SearchEngine.bing),
          ['https://fallback-vod.com']);
    });
  });

  group('friendLinkBases', () {
    test('同主机内链剔除，外链保留', () {
      const html = '''
<a href="https://friend-a.com/">友链A</a>
<a href="https://self-site.com/page">内链</a>
<a href="https://www.bing.com/">搜索引擎</a>
<a href="//friend-b.com/x">友链B</a>
''';
      expect(
        SiteDiscoveryService.friendLinkBases(html, 'https://self-site.com'),
        ['https://friend-a.com', 'https://friend-b.com'],
      );
    });
  });

  group('githubRepoBases / urlsInText', () {
    test('取 homepage 与描述里的域名，过滤伪域名', () {
      const json = '''
{"items":[
 {"homepage":"https://home-site.com","description":"maccms 采集 https://desc-site.org/api"},
 {"homepage":"","description":"没有任何地址"},
 {"homepage":"not a url","description":"use api.php for data"}
]}''';
      expect(SiteDiscoveryService.githubRepoBases(json),
          ['https://home-site.com', 'https://desc-site.org']);
    });

    test('非法响应返回空', () {
      expect(SiteDiscoveryService.githubRepoBases('not json'), isEmpty);
      expect(SiteDiscoveryService.githubRepoBases('{"total_count":1}'), isEmpty);
    });

    test('自由文本抽域名', () {
      expect(SiteDiscoveryService.urlsInText('see https://x-y.org/a now'),
          ['https://x-y.org']);
      expect(SiteDiscoveryService.urlsInText('plain words only'), isEmpty);
    });

    test('maccmsApiBases：只收带 maccms 路径的地址，忽略普通链接', () {
      const text = '''
接口A：https://api.one.com/api.php/provide/vod/?ac=list
备用B：http://two.com:8080/api.php/provide/vod/
详情C：https://three.com/voddetail/123.html
普通D：https://docs.four.com/guide  和  https://cdn.five.com/lib.js
模板E：`https://six.com/api.php/provide/vod`''';
      expect(SiteDiscoveryService.maccmsApiBases(text), [
        'https://api.one.com',
        'http://two.com:8080',
        'https://three.com',
        'https://six.com',
      ]);
      expect(SiteDiscoveryService.maccmsApiBases('只有普通网址 https://x.com/a'),
          isEmpty);
    });

    test('githubReadmeTargets：取合法仓库全名、按题材过滤并限流', () {
      const json = '''
{"items":[
 {"full_name":"abc/maccms-list"},
 {"full_name":"oops"},
 {"full_name":"bad name/x y"},
 {"full_name":"cirosantilli/china-dictatorship","description":"榜单"},
 {"homepage":"https://h.com","full_name":"def/vod-list","description":"影视接口"}
]}''';
      expect(SiteDiscoveryService.githubReadmeTargets(json, limit: 2),
          ['abc/maccms-list', 'def/vod-list']);
      expect(SiteDiscoveryService.githubReadmeTargets('not json'), isEmpty);
      expect(SiteDiscoveryService.githubReadmeTargets('{"total_count":3}'), isEmpty);
    });
  });

  // ==================== 查询串 ====================

  group('查询串', () {
    test('搜索引擎查询：首条为接口路径精确短语，第二条带关键词', () {
      final qs = SiteDiscoveryService.engineQueries('短剧');
      expect(qs.length, 2);
      expect(qs.first, '"api.php/provide/vod"');
      expect(qs.last, contains('短剧'));
      expect(SiteDiscoveryService.engineQueries('   '), ['"api.php/provide/vod"']);
    });

    test('GitHub 查询控制在 3 条内（匿名限流 10 次/分）', () {
      final qs = SiteDiscoveryService.githubQueries('古装');
      expect(qs.length, 3);
      expect(qs[0], contains('in:readme'));
      expect(qs.last, contains('古装'));
      expect(SiteDiscoveryService.githubQueries('   ').length, 2);
      expect(SiteDiscoveryService.githubSearchUrl('maccms 采集'),
          contains('api.github.com/search/repositories'));
    });
  });

  // ==================== 订阅解析 ====================

  group('parseSubscription', () {
    test('对象形态 {"sites":[...]}，地址字段宽容', () {
      final items = SiteDiscoveryService.parseSubscription('''
{"name":"我的订阅","sites":[
  {"name":"源A","base":"https://a.com"},
  {"url":"b.com/x","title":"源B"},
  {"api":"http://c.com:8080","mode":"html"}
]}''');
      expect(items.length, 3);
      expect(items[0].base, 'https://a.com');
      expect(items[0].name, '源A');
      expect(items[0].source, DiscoverySource.subscription);
      expect(items[1].base, 'https://b.com');
      expect(items[1].name, '源B');
      expect(items[2].base, 'http://c.com:8080');
    });

    test('顶层数组形态 + 同主机去重 + 非法地址跳过', () {
      final items = SiteDiscoveryService.parseSubscription('''
[
  {"base":"https://d.com"},
  {"base":"https://www.d.com/other"},
  {"base":"/not-a-site"},
  {"base":"https://duckduckgo.com/x"}
]''');
      expect(items.length, 1);
      expect(items.single.base, 'https://d.com');
    });

    test('格式非法抛 FormatException', () {
      expect(() => SiteDiscoveryService.parseSubscription('not json'),
          throwsFormatException);
      expect(() => SiteDiscoveryService.parseSubscription('{"foo":1}'),
          throwsFormatException);
      expect(() => SiteDiscoveryService.parseSubscription('{"sites":[]}'),
          throwsFormatException);
    });
  });

  // ==================== 合并与排序 ====================

  group('knownHostKeys / mergeCandidates / sortCandidates', () {
    test('已知站点包含内置与自定义', () {
      final keys = SiteDiscoveryService.knownHostKeys();
      expect(keys, contains('bsvod.com'));
      expect(keys, contains('bhvod.com'));
      expect(keys, isNot(contains('brand-new.com')));
    });

    test('合并：同主机去重、已存在的标为 known', () async {
      await PlayLineResolver.addCustom(
          name: '我的站', base: 'https://mine.com', mode: PlayLineMode.api);
      final current = [
        SiteCandidate(
            base: 'https://a.com',
            host: 'a.com',
            source: DiscoverySource.engine)
          ..status = CandidateStatus.ok,
      ];
      final merged = SiteDiscoveryService.mergeCandidates(current, [
        SiteCandidate(
            base: 'https://a.com',
            host: 'a.com',
            source: DiscoverySource.subscription),
        SiteCandidate(
            base: 'https://bsvod.com',
            host: 'bsvod.com',
            source: DiscoverySource.engine),
        SiteCandidate(
            base: 'https://mine.com',
            host: 'mine.com',
            source: DiscoverySource.friend),
        SiteCandidate(
            base: 'https://brand-new.com',
            host: 'brand-new.com',
            source: DiscoverySource.github),
      ]);
      expect(merged.length, 4);
      expect(merged.where((c) => c.host == 'a.com').length, 1);
      expect(
          merged.firstWhere((c) => c.host == 'a.com').status,
          CandidateStatus.ok);
      expect(merged.firstWhere((c) => c.host == 'bsvod.com').status,
          CandidateStatus.known);
      expect(merged.firstWhere((c) => c.host == 'mine.com').status,
          CandidateStatus.known);
      expect(merged.firstWhere((c) => c.host == 'brand-new.com').status,
          CandidateStatus.pending);
    });

    test('排序：可用 → 探测中 → 待探测 → 已存在 → 失败', () {
      SiteCandidate make(CandidateStatus s) => SiteCandidate(
          base: 'https://x.com', host: 'x.com', source: DiscoverySource.engine)
        ..status = s;
      final sorted = SiteDiscoveryService.sortCandidates([
        make(CandidateStatus.failed),
        make(CandidateStatus.known),
        make(CandidateStatus.ok),
        make(CandidateStatus.pending),
        make(CandidateStatus.probing),
      ]);
      expect(sorted.map((c) => c.status).toList(), [
        CandidateStatus.ok,
        CandidateStatus.probing,
        CandidateStatus.pending,
        CandidateStatus.known,
        CandidateStatus.failed,
      ]);
    });
  });

  // ==================== 候选模型 ====================

  group('SiteCandidate', () {
    test('展示名优先取订阅名称，回退主机名', () {
      final c = SiteCandidate(
          base: 'https://a.com', host: 'a.com', source: DiscoverySource.engine);
      expect(c.displayName, 'a.com');
      expect(c.selectable, isFalse);
      c
        ..status = CandidateStatus.ok
        ..mode = PlayLineMode.api
        ..selected = true;
      expect(c.selectable, isTrue);
      c.name = '源A';
      expect(c.displayName, '源A');
    });

    test('来源标签', () {
      expect(DiscoverySource.engine.label, '搜索');
      expect(DiscoverySource.github.label, 'GitHub');
      expect(DiscoverySource.friend.label, '友链');
      expect(DiscoverySource.subscription.label, '订阅');
    });
  });
}
