import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/play_lines.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 遗留线路定点复测（线上诊断）：此前因详情页剧名校验 / 瞬时网络失败而挂的线路。
/// 只打印结果不设网络断言（限流会造成抖动），供回归观察。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    PlayLineResolver.clearCaches();
  });

  test('定点复测 thjzsj/danbotv/lvvod', () async {
    const lines = ['thjzsj.cn', 'danbotv.com', 'lvvod.com'];
    const cases = <({String title, int ep})>[
      (title: '万妖图录传第十三季', ep: 12),
      (title: '重生！丑小鸭逆袭成了万人迷第三季', ep: 12),
    ];

    for (final id in lines) {
      final line = PlayLineResolver.byId(id);
      expect(line, isNotNull, reason: '线路 $id 应已注册');
      var ok = 0;
      for (final c in cases) {
        final sw = Stopwatch()..start();
        try {
          final url = await PlayLineResolver.resolve(
            title: c.title,
            episodeIndex: c.ep,
            onLine: line,
          );
          ok++;
          // ignore: avoid_print
          print('SPOT ${id.padRight(14)} ${c.title} ep${c.ep} -> '
              'OK   ${sw.elapsedMilliseconds}ms host=${Uri.parse(url).host}');
        } catch (e) {
          // ignore: avoid_print
          print('SPOT ${id.padRight(14)} ${c.title} ep${c.ep} -> '
              'FAIL ${sw.elapsedMilliseconds}ms '
              '${e.toString().replaceFirst('Exception: ', '')}');
        }
      }
      // ignore: avoid_print
      print('SPOT-SUMMARY $id $ok/${cases.length}');
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
