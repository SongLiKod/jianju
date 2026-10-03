import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/constants/api_constants.dart';
import 'package:jianju/core/services/api_service.dart';

/// 线上数据源联通性测试：验证 SSR 解析与各业务接口仍可用
void main() {
  /// 线上源偶发返回空壳，失败时整体重试
  Future<T> retry<T>(Future<T> Function() run, {int tries = 3}) async {
    Object? last;
    for (var i = 0; i < tries; i++) {
      try {
        return await run();
      } catch (e) {
        last = e;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    throw last!;
  }

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

  test('分类第一页各类型有数据', () async {
    for (final slug in ApiConstants.categorySlugs) {
      final items = await ApiService.fetchCategory(slug: slug, page: 1);
      // ignore: avoid_print
      print('category $slug: ${items.length} 条, 首条=${items.firstOrNull?.title}');
      expect(items, isNotEmpty, reason: '分类 $slug 应有数据');
      expect(items.first.coverUrl, isNotEmpty);
    }
  });

  test('排行榜各榜单有数据且带热度', () async {
    for (final slug in ApiConstants.rankSlugs) {
      final r = await retry(() => ApiService.fetchRank(slug: slug, page: 1));
      // ignore: avoid_print
      print('rank $slug: ${r.items.length} 条, 页数=${r.totalPages}, '
          '更新=${r.updatedText}, 首条=${r.items.firstOrNull?.title} '
          '${r.items.firstOrNull?.readCountText}');
      expect(r.items, isNotEmpty, reason: '榜单 $slug 应有数据');
      expect(r.items.first.coverUrl, isNotEmpty);
      expect(r.items.first.readCountText, isNotEmpty, reason: '榜单条目应带热度');
    }
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('排行榜翻页返回不同条目', () async {
    final p1 = await retry(() => ApiService.fetchRank(slug: 'hot-drama', page: 1));
    final p2 = await retry(() => ApiService.fetchRank(slug: 'hot-drama', page: 2));
    // ignore: avoid_print
    print('rank page2: ${p2.items.length} 条');
    expect(p2.items, isNotEmpty);
    expect(p2.items.first.bookId, isNot(p1.items.first.bookId));
  }, timeout: const Timeout(Duration(minutes: 4)));

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
