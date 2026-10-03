import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/play_lines.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内置线路线上解析测试：真实站点端到端（搜索 → 详情 → 播放页 → m3u8）
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    PlayLineResolver.clearCaches();
  });

  test('自动模式解析到可用直链', () async {
    final url = await PlayLineResolver.resolve(
      title: '宴律，你的白月光回国了',
      episodeIndex: 40,
    );
    // ignore: avoid_print
    print('auto line: ${PlayLineResolver.lastUsedLine?.id} -> $url');
    expect(url, startsWith('http'));
    expect(PlayLineResolver.lastUsedLine, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('锁定单条线路也可解析', () async {
    SharedPreferences.setMockInitialValues(
        {'settings.pinned_line': 'bcvod.one'});
    await StorageService.init();
    PlayLineResolver.clearCaches();

    final url = await PlayLineResolver.resolve(
      title: '宴律，你的白月光回国了',
      episodeIndex: 5,
    );
    // ignore: avoid_print
    print('pinned line: ${PlayLineResolver.lastUsedLine?.id} -> $url');
    expect(url, startsWith('http'));
    expect(PlayLineResolver.lastUsedLine?.id, 'bcvod.one');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
