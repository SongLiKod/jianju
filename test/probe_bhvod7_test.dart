import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/prebuffer_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 真实 bhvod 流复验：同目录片尾贴片必须被码率判据剔除
///
/// ep1 直链：正片 27 片 107.2s（1138kbps）+ DISCONTINUITY + 片尾贴片
/// 4 片 16.5s（3238kbps，跨集字节完全相同），目录相同 → 老规则漏判。
class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

void main() {
  setUp(() {
    PathProviderPlatform.instance = _FakePathProvider();
  });

  test('bhvod 惊悚boss ep1 起播改写剔除同目录片尾贴片', () async {
    const url =
        'https://player.yzzyssvip-36.com/20261004/560166_87be18f4/index.m3u8';
    final local = await PrebufferService.rewritePlaylist(url);
    // ignore: avoid_print
    print('local=${local ?? "null（原样起播——判据未命中）"}');
    expect(local, isNotNull, reason: '同目录贴片应被码率判据剔除');
    final text = await File(local!).readAsString();
    // ignore: avoid_print
    print('lines=${text.split('\n').length} '
        'bytes=${text.length} '
        'ad=${text.contains('45e6f0500de3fad6bec40363bf63516b.ts')}');
    expect(text, isNot(contains('45e6f0500de3fad6bec40363bf63516b.ts')),
        reason: '片尾贴片首片应被剔除');
    expect(text, contains('#EXT-X-ENDLIST'));
    var secs = 0.0;
    final segs = <String>[];
    for (final raw in text.split('\n')) {
      final l = raw.trim();
      if (l.toUpperCase().startsWith('#EXTINF:')) {
        secs += double.tryParse(l.substring(8).split(',').first) ?? 0;
      } else if (l.isNotEmpty && !l.startsWith('#')) {
        segs.add(l);
      }
    }
    // ignore: avoid_print
    print('总时长 ${secs.toStringAsFixed(1)}s / ${segs.length} 片');
    expect(secs, greaterThan(100), reason: '正片应保留');
    expect(segs.length, lessThanOrEqualTo(27), reason: '4 片贴片应已剔除');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
