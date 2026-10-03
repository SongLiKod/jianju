import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/api_service.dart';
import 'package:jianju/core/services/play_lines.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 线路 × 剧目矩阵（线上）：逐条线路验证指定剧目能否解析出直链
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    PlayLineResolver.clearCaches();
  });

  test('线路×剧目矩阵', () async {
    const titles = [
      '万妖图录传第十三季',
      '重生！丑小鸭逆袭成了万人迷第三季',
      '二嫁有喜',
    ];

    final cases = <({String title, int ep})>[];
    for (final t in titles) {
      final items = await ApiService.search(keyword: t);
      if (items.isEmpty) {
        // ignore: avoid_print
        print('CASE 官方搜索无结果: $t');
        continue;
      }
      final hit = items.firstWhere(
        (d) => d.title.contains(t) || t.contains(d.title),
        orElse: () => items.first,
      );
      final detail = await ApiService.fetchDetail(hit.bookId);
      final n = detail.episodes.length;
      final ep = n >= 12 ? 12 : n;
      cases.add((title: hit.title, ep: ep));
      // ignore: avoid_print
      print('CASE ${hit.title} | 官方集数=$n | 测第$ep集');
    }
    expect(cases, isNotEmpty);

    final fails = <String>[];
    final wrong = <String>[];
    for (final line in kPlayLines) {
      var ok = 0;
      final urls = <String, String>{}; // title|ep -> url
      for (final c in cases) {
        final sw = Stopwatch()..start();
        String res;
        try {
          final url = await PlayLineResolver.resolve(
            title: c.title,
            episodeIndex: c.ep,
            onLine: line,
          );
          ok++;
          final tag = '${c.title}@${c.ep}';
          if (urls.containsValue(url)) {
            res = 'WRONG 同一线路不同剧返回同一地址 ${sw.elapsedMilliseconds}ms $url';
            wrong.add('${line.id}|$tag|$url');
          } else {
            urls[tag] = url;
            res = 'OK   ${sw.elapsedMilliseconds}ms host=${Uri.parse(url).host}';
          }
        } catch (e) {
          res = 'FAIL ${sw.elapsedMilliseconds}ms ${e.toString().replaceFirst('Exception: ', '')}';
          fails.add('${line.id}|${c.title}|${c.ep}');
        }
        // ignore: avoid_print
        print('LINE ${line.id.padRight(16)} ${c.title} ep${c.ep} -> $res');
      }
      // ignore: avoid_print
      print('SUMMARY ${line.id.padRight(16)} $ok/${cases.length}');
    }

    // 自动模式（应用默认行为）
    for (final c in cases) {
      final sw = Stopwatch()..start();
      try {
        final url = await PlayLineResolver.resolve(
            title: c.title, episodeIndex: c.ep);
        // ignore: avoid_print
        print('AUTO ${c.title} ep${c.ep} -> ${sw.elapsedMilliseconds}ms '
            'line=${PlayLineResolver.lastUsedLine?.id} host=${Uri.parse(url).host}');
      } catch (e) {
        // ignore: avoid_print
        print('AUTO ${c.title} ep${c.ep} -> FAIL ${e.toString()}');
      }
    }

    // ignore: avoid_print
    print('TOTAL FAIL ${fails.length} WRONG ${wrong.length}');
    for (final f in fails) {
      // ignore: avoid_print
      print('  - $f');
    }
    for (final w in wrong) {
      // ignore: avoid_print
      print('  * $w');
    }
  }, timeout: const Timeout(Duration(minutes: 40)));
}
