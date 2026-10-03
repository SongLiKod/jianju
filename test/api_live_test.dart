import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/api_service.dart';

/// 线上数据源联通性测试：验证 SSR 解析与各业务接口仍可用
void main() {
  test('首页信息流有数据', () async {
    final items = await ApiService.fetchHomeFeed(page: 0);
    // ignore: avoid_print
    print('home feed: ${items.length} 条');
    for (final d in items.take(3)) {
      // ignore: avoid_print
      print('  - ${d.title} | ${d.episodeCount}集 | ${d.coverUrl}');
    }
    expect(items, isNotEmpty);
    expect(items.first.coverUrl, isNotEmpty);
  });

  test('分类分页有数据', () async {
    final items = await ApiService.fetchCategory(slug: 'real-drama', page: 2);
    // ignore: avoid_print
    print('category page2: ${items.length} 条');
    expect(items, isNotEmpty);
  });

  test('搜索有数据', () async {
    final items = await ApiService.search(keyword: '高冷');
    // ignore: avoid_print
    print('search: ${items.length} 条');
    expect(items, isNotEmpty);
  });

  test('详情与分集有数据', () async {
    final home = await ApiService.fetchHomeFeed(page: 0);
    final id = home.first.bookId;
    final detail = await ApiService.fetchDetail(id);
    // ignore: avoid_print
    print('detail $id: drama=${detail.drama?.title}, '
        'episodes=${detail.episodes.length}, related=${detail.related.length}');
    expect(detail.drama, isNotNull);
    expect(detail.episodes, isNotEmpty);
    expect(detail.related, isNotEmpty);
  });

  test('播放地址可获取', () async {
    final home = await ApiService.fetchHomeFeed(page: 0);
    final id = home.first.bookId;
    final detail = await ApiService.fetchDetail(id);
    final vid = detail.episodes.first.itemId;
    final url = await ApiService.fetchPlayUrl(seriesId: id, vid: vid);
    // ignore: avoid_print
    print('play url: $url');
    expect(url, startsWith('http'));
  });
}
