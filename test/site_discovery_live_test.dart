import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/play_lines.dart';
import 'package:jianju/core/services/site_discovery_service.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 联网用例：真实从公网查找候选资源站（搜索引擎 + GitHub + 友链）并探测。
///
/// 运行：flutter test test/site_discovery_live_test.dart
///
/// 注意：本文件**不能**初始化 TestWidgetsFlutterBinding（会把 HttpClient 打成 400）。
/// 引擎被拦截属于常态，因此只断言「解析出了候选」，可用数靠打印排查。
void main() {
  const timeout = Timeout(Duration(minutes: 6));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    PlayLineResolver.resetCustomLinesForTest();
  });

  // ignore: avoid_print
  void log(String s) => print(s);

  test('在线发现：三来源查找 + 批量探测', () async {
    final items = await SiteDiscoveryService.discover(
      const DiscoveryRequest(keyword: '短剧'),
      onNote: log,
    );
    log('DISCOVERY candidates=${items.length}');
    for (final c in items) {
      log('  ${c.status.name.padRight(8)} ${c.source.name.padRight(12)} '
          '${c.base} ${c.latencyMs ?? 0}ms '
          '${c.sampleTitle ?? c.failReason ?? ''}');
    }
    final ok = items.where((c) => c.status == CandidateStatus.ok).length;
    log('DISCOVERY ok=$ok / ${items.length}');
    expect(items, isNotEmpty, reason: '至少应解析出候选站点');
  }, timeout: timeout);

  test('自动模式探测：标准接口站点判定为 api 模式', () async {
    final probe = await PlayLineResolver.probeAuto('https://bsvod.com');
    log('PROBE bsvod.com -> ok=${probe.ok} mode=${probe.mode} '
        '${probe.latencyMs}ms ${probe.sampleTitle ?? probe.reason}');
    expect(probe.ok, isTrue);
    expect(probe.mode, PlayLineMode.api);
    expect(probe.sampleTitle, isNotNull);
  }, timeout: timeout);

  test('自动模式探测：网页解析站点在线时判定为 html 模式', () async {
    // 内置网页解析站可能因改版/下线不在线，逐个试，全不在线则只打印不硬断言
    const bases = ['https://thjzsj.cn', 'https://bcvod.top', 'https://bgmov.com'];
    var detected = false;
    for (final base in bases) {
      final probe = await PlayLineResolver.probeAuto(base);
      log('PROBE $base -> ok=${probe.ok} mode=${probe.mode} '
          '${probe.latencyMs}ms ${probe.sampleTitle ?? probe.reason}');
      if (probe.ok) {
        expect(probe.mode, PlayLineMode.html);
        detected = true;
        break;
      }
    }
    if (!detected) {
      log('内置网页解析站当前均不在线，本条仅作诊断（不设网络断言）');
    }
  }, timeout: timeout);
}
