import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/constants/app_constants.dart';
import 'package:jianju/core/services/api_service.dart';
import 'package:jianju/core/services/play_lines.dart';
import 'package:jianju/core/services/settings_service.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全部整站 API 线逐一切换审计：tabs / 首页 / 分页 / 分类 / 榜单 / 搜索 / 详情 / 播放。
///
/// 每步独立容错并打印 AUDIT 行，最后汇总；整体仅要求过半线路全绿，
/// 死线/坏步从输出可见便于处理。
///
/// 注意：本文件**不能**初始化 TestWidgetsFlutterBinding（会把 HttpClient 打成 400）。
void main() {
  const timeout = Timeout(Duration(minutes: 8));
  final lines =
      kPlayLines.where((l) => l.mode == PlayLineMode.api).toList();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  tearDown(() async {
    await SettingsService.setDataSource(AppConstants.dataSourceWeb);
  });

  test('整站源全链路审计（${lines.length} 条）', () async {
    final fully = <String>[];
    final summary = <String>[];

    for (final line in lines) {
      await SettingsService.setDataSource(
          AppConstants.dataSourceOfLine(line.id));
      final bad = <String>[];
      String? bookId;
      String? bookTitle;
      String? firstEpItemId;
      var epCount = 0;

      Future<void> step(String name, Future<void> Function() fn) async {
        final sw = Stopwatch()..start();
        try {
          await fn();
          // ignore: avoid_print
          print('AUDIT ${line.id.padRight(16)} $name '
              'OK   ${sw.elapsedMilliseconds}ms');
        } catch (e) {
          final msg = e
              .toString()
              .replaceFirst('Exception: ', '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .truncate(80);
          bad.add('$name($msg)');
          // ignore: avoid_print
          print('AUDIT ${line.id.padRight(16)} $name '
              'FAIL ${sw.elapsedMilliseconds}ms $msg');
        }
      }

      await step('tabs', () async {
        final tabs = await ApiService.fetchCategoryLabels();
        if (tabs.isEmpty) throw Exception('空 tabs');
        if (tabs.values.any((v) => v.trim().isEmpty)) {
          throw Exception('含空标签');
        }
      });

      await step('home', () async {
        final items = await ApiService.fetchHomeFeed(page: 0);
        if (items.isEmpty) throw Exception('首页空');
        bookId ??= items.first.bookId;
        bookTitle ??= items.first.title;
      });

      await step('home2', () async {
        final items = await ApiService.fetchHomeFeed(page: 1);
        if (items.isEmpty) throw Exception('第2页空');
      });

      await step('category', () async {
        final tabs = await ApiService.fetchCategoryLabels();
        final items =
            await ApiService.fetchCategory(slug: tabs.keys.first, page: 1);
        if (items.isEmpty) throw Exception('分类空');
      });

      await step('cat_p2', () async {
        final tabs = await ApiService.fetchCategoryLabels();
        final items =
            await ApiService.fetchCategory(slug: tabs.keys.first, page: 2);
        if (items.isEmpty) throw Exception('分类第2页空');
      });

      await step('rank', () async {
        final labels = await ApiService.fetchRankLabels();
        final r = await ApiService.fetchRank(slug: labels.keys.first, page: 1);
        if (r.items.isEmpty) throw Exception('榜单空');
        if (r.totalPages < 1) throw Exception('页数异常 ${r.totalPages}');
      });

      await step('search', () async {
        final items = await ApiService.search(keyword: '二嫁有喜');
        if (items.isEmpty) throw Exception('搜索无结果');
        bookId ??= items.first.bookId;
        bookTitle ??= items.first.title;
      });

      await step('detail', () async {
        final id = bookId;
        if (id == null) throw Exception('无剧目可测');
        final d = await ApiService.fetchDetail(id);
        if (d.drama == null) throw Exception('详情为空');
        if (d.episodes.isEmpty) throw Exception('分集为空');
        epCount = d.episodes.length;
        firstEpItemId = d.episodes.first.itemId;
      });

      await step('play', () async {
        final id = bookId;
        final ep = firstEpItemId;
        final title = bookTitle;
        if (id == null || ep == null) throw Exception('缺详情数据');
        final url = await ApiService.fetchPlayUrl(
          seriesId: id,
          vid: ep,
          title: title,
          episodeIndex: 1,
        );
        if (!url.startsWith('http')) throw Exception('非法地址');
      });

      if (bad.isEmpty) fully.add(line.id);
      summary.add('${line.id.padRight(16)} '
          '${bad.isEmpty ? "FULL OK" : "BAD: ${bad.join(', "')}"}'
          '${epCount > 0 ? " | $epCount 集" : ''}');
    }

    // ignore: avoid_print
    print('===== 整站源审计汇总 =====');
    for (final s in summary) {
      // ignore: avoid_print
      print('  $s');
    }
    // ignore: avoid_print
    print('FULL OK ${fully.length}/${lines.length}: $fully');

    expect(fully.length, greaterThanOrEqualTo(lines.length ~/ 2),
        reason: '全链路通过的整站源不足半数，需处理死源');
  }, timeout: timeout);
}

extension on String {
  String truncate(int n) => length <= n ? this : substring(0, n);
}
