import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/constants/app_constants.dart';
import 'package:jianju/core/services/api_service.dart';
import 'package:jianju/core/services/settings_service.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 整站数据源线上冒烟：分类 tab / 首页 / 分类 / 榜单 / 搜索 / 详情 / 播放
/// 全链路走 maccms 站点（bsvod.com），验证接口契约与解析逻辑
///
/// 注意：本文件**不能**初始化 TestWidgetsFlutterBinding——它会把所有
/// HttpClient 请求改为 HTTP 400（参照 api_live_test）。
void main() {
  const site = 'bsvod.com';
  const timeout = Timeout(Duration(minutes: 2));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    await SettingsService.setDataSource(AppConstants.dataSourceOfLine(site));
  });

  tearDown(() async {
    await SettingsService.setDataSource(AppConstants.dataSourceWeb);
  });

  test('分类 tab 取自站点 class', () async {
    final tabs = await ApiService.fetchCategoryLabels();
    // ignore: avoid_print
    print('tabs: $tabs');
    expect(tabs, isNotEmpty);
    expect(tabs.values.every((v) => v.isNotEmpty), isTrue);
  }, timeout: timeout);

  test('首页信息流有数据且带 mg 前缀', () async {
    final items = await ApiService.fetchHomeFeed(page: 0);
    // ignore: avoid_print
    print('home: ${items.length} 条, 首条=${items.firstOrNull?.title}');
    expect(items, isNotEmpty);
    expect(items.first.bookId, startsWith('mg:$site:'));
    expect(items.first.coverUrl, isNotEmpty);
  }, timeout: timeout);

  test('分类分页有数据', () async {
    final tabs = await ApiService.fetchCategoryLabels();
    final slug = tabs.keys.first;
    final items = await ApiService.fetchCategory(slug: slug, page: 2);
    // ignore: avoid_print
    print('category $slug page2: ${items.length} 条');
    expect(items, isNotEmpty);
  }, timeout: timeout);

  test('榜单按热度有数据', () async {
    final labels = await ApiService.fetchRankLabels();
    final slug = labels.keys.first;
    final result = await ApiService.fetchRank(slug: slug, page: 1);
    // ignore: avoid_print
    print('rank $slug: ${result.items.length} 条 / ${result.totalPages} 页, '
        '${result.updatedText}');
    expect(result.items, isNotEmpty);
    expect(result.totalPages, greaterThanOrEqualTo(1));
  }, timeout: timeout);

  test('搜索命中同名剧且带 mg 前缀', () async {
    final items = await ApiService.search(keyword: '二嫁有喜');
    // ignore: avoid_print
    print('search: ${items.map((d) => d.title).take(5).toList()}');
    expect(items, isNotEmpty);
    expect(items.first.bookId, startsWith('mg:$site:'));
  }, timeout: timeout);

  test('详情 → 分集 → 播放直链全链路', () async {
    final found = await ApiService.search(keyword: '二嫁有喜');
    expect(found, isNotEmpty);
    final detail =
        await ApiService.fetchDetail(found.first.bookId);
    // ignore: avoid_print
    print('detail: ${detail.drama?.title} / '
        '${detail.episodes.length} 集 / 推荐 ${detail.related.length}');
    expect(detail.drama, isNotNull);
    expect(detail.episodes, isNotEmpty);
    expect(detail.episodes.first.itemId, startsWith('mg:$site:'));

    final ep = detail.episodes.first;
    final url = await ApiService.fetchPlayUrl(
      seriesId: found.first.bookId,
      vid: ep.itemId,
      title: detail.drama!.title,
      episodeIndex: ep.index,
    );
    // ignore: avoid_print
    print('play ${ep.title}: $url');
    expect(url, startsWith('http'));
  }, timeout: timeout);
}
