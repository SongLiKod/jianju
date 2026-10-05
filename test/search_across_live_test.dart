import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/api_service.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 跨站搜索线上诊断：并发搜索官方源 + 全部整站站点，
/// 验证结果能边搜边出、去重合并且不超过配置条数。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  test('跨站搜索聚合', () async {
    var updates = 0;
    var lastDone = 0;
    var total = 0;
    final items = await ApiService.searchAcross(
      keyword: '庆余年',
      limit: 20,
      onUpdate: (merged, done, all) {
        updates++;
        lastDone = done;
        total = all;
        // ignore: avoid_print
        print('UPDATE done=$done/$all merged=${merged.length}');
      },
    );
    // ignore: avoid_print
    print('TOTAL ${items.length} 条 · 更新 $updates 次 · 完成 $lastDone/$total');
    for (final d in items) {
      // ignore: avoid_print
      print('  ${d.bookId} | ${d.title}');
    }
    expect(items, isNotEmpty, reason: '跨站搜索至少应有 1 条结果');
    expect(items.length, lessThanOrEqualTo(20));
    expect(total, greaterThan(1), reason: '应覆盖多个站点');
    expect(updates, greaterThan(1), reason: '结果应随站点返回逐步更新');
  }, timeout: const Timeout(Duration(minutes: 1)));
}
