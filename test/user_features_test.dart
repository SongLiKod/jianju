import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/constants/app_constants.dart';
import 'package:jianju/core/models/drama.dart';
import 'package:jianju/core/services/history_service.dart';
import 'package:jianju/core/services/play_lines.dart';
import 'package:jianju/core/services/search_history_service.dart';
import 'package:jianju/core/services/settings_service.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:jianju/core/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Drama _drama(String id) => Drama(
      bookId: id,
      title: '测试剧$id',
      coverUrl: '',
      abstractText: '',
      tags: const [],
      episodeCount: 12,
      readCountText: '',
      statusText: '',
      categoryText: '',
    );

/// 新增用户功能的离线行为：
/// 播放体验设置 / 历史管理 / 搜索历史 / 自定义站点
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    HistoryService.init();
    SearchHistoryService.init();
    PlayLineResolver.resetCustomLinesForTest();
  });

  // ==================== 播放体验设置 ====================

  group('播放体验设置', () {
    test('默认值：预载开/10秒/缓冲20秒/进度条开', () {
      final p = SettingsProvider()..load();
      expect(p.preloadNext, isTrue);
      expect(p.preloadLeadSec, 10);
      expect(p.bufferSecs, 20);
      expect(p.slimProgress, isTrue);
    });

    test('修改后立即生效并持久化', () async {
      final p = SettingsProvider()..load();
      await p.setPreloadNext(false);
      await p.setPreloadLeadSec(30);
      await p.setBufferSecs(180);
      await p.setSlimProgress(false);
      expect(p.preloadNext, isFalse);
      expect(p.preloadLeadSec, 30);
      expect(p.bufferSecs, 180);
      expect(p.slimProgress, isFalse);

      final fresh = SettingsProvider()..load();
      expect(fresh.preloadNext, isFalse);
      expect(fresh.preloadLeadSec, 30);
      expect(fresh.bufferSecs, 180);
      expect(fresh.slimProgress, isFalse);
    });

    test('非法存储值回退默认（不在候选项内）', () async {
      await SettingsService.setPreloadLeadSec(7); // 不在 [5,10,15,30,60]
      await SettingsService.setBufferSecs(999); // 不在 [10,20,60,180]
      expect(SettingsService.preloadLeadSec, AppConstants.defaultPreloadLeadSec);
      expect(SettingsService.bufferSecs, AppConstants.defaultBufferSecs);
    });
  });

  // ==================== 观看历史管理 ====================

  group('观看历史管理', () {
    test('单条删除与清空', () async {
      await HistoryService.upsert(_drama('a'),
          episodeIndex: 1, episodeItemId: 'a1', positionMs: 5000);
      await HistoryService.upsert(_drama('b'),
          episodeIndex: 2, episodeItemId: 'b1', positionMs: 0);
      expect(HistoryService.history.length, 2);

      await HistoryService.remove('a');
      expect(HistoryService.history.length, 1);
      expect(HistoryService.recordOf('a'), isNull);
      expect(HistoryService.recordOf('b'), isNotNull);

      await HistoryService.clear();
      expect(HistoryService.history, isEmpty);
      // 持久化：重新加载仍为空
      HistoryService.init();
      expect(HistoryService.history, isEmpty);
    });
  });

  // ==================== 搜索历史管理 ====================

  group('搜索历史', () {
    test('记录、去重置顶、上限截断', () async {
      await SearchHistoryService.add('宴律');
      await SearchHistoryService.add('庆余年');
      await SearchHistoryService.add('宴律');
      expect(SearchHistoryService.items.first, '宴律');
      expect(SearchHistoryService.items.where((e) => e == '宴律').length, 1);

      for (var i = 0; i < AppConstants.maxSearchHistory + 5; i++) {
        await SearchHistoryService.add('关键词$i');
      }
      expect(
          SearchHistoryService.items.length, AppConstants.maxSearchHistory);
      expect(SearchHistoryService.items.first,
          '关键词${AppConstants.maxSearchHistory + 4}');
    });

    test('空关键词不记录', () async {
      await SearchHistoryService.add('   ');
      expect(SearchHistoryService.items, isEmpty);
    });

    test('单条删除与清空（含持久化）', () async {
      await SearchHistoryService.add('甲');
      await SearchHistoryService.add('乙');
      await SearchHistoryService.remove('甲');
      expect(SearchHistoryService.items, ['乙']);
      await SearchHistoryService.clear();
      expect(SearchHistoryService.items, isEmpty);
      SearchHistoryService.init();
      expect(SearchHistoryService.items, isEmpty);
    });
  });

  // ==================== 自定义站点 ====================

  group('自定义站点', () {
    test('地址归一化与 id 生成（id 不含冒号，避免破坏整站源 ID 分派）', () {
      expect(PlayLineResolver.normalizeBase('example.com/'), 'https://example.com');
      expect(PlayLineResolver.normalizeBase('http://a.com//'), 'http://a.com');
      expect(PlayLineResolver.normalizeBase('  https://b.com  '), 'https://b.com');
      expect(PlayLineResolver.customIdFor('https://Example.com/path'),
          'custom-example.com');
      expect(PlayLineResolver.customIdFor('https://example.com').contains(':'),
          isFalse);
    });

    test('添加后进入 allLines/byId，删除后移除', () async {
      await PlayLineResolver.addCustom(
        name: '我的站',
        base: 'https://site1.com',
        mode: PlayLineMode.api,
      );
      expect(
          PlayLineResolver.allLines
              .where((l) => l.id == 'custom-site1.com')
              .length,
          1);
      final found = PlayLineResolver.byId('custom-site1.com');
      expect(found, isNotNull);
      expect(found!.name, '我的站');
      expect(found.mode, PlayLineMode.api);
      expect(found.isCustom, isTrue);
      expect(PlayLineResolver.customLines.length, 1);

      await PlayLineResolver.removeCustom('custom-site1.com');
      expect(PlayLineResolver.byId('custom-site1.com'), isNull);
      expect(PlayLineResolver.customLines, isEmpty);
    });

    test('同主机重复添加为覆盖而非追加', () async {
      await PlayLineResolver.addCustom(
          name: '旧名', base: 'https://dup.com', mode: PlayLineMode.api);
      await PlayLineResolver.addCustom(
          name: '新名', base: 'https://dup.com/', mode: PlayLineMode.html);
      expect(PlayLineResolver.customLines.length, 1);
      expect(PlayLineResolver.customLines.first.name, '新名');
      expect(PlayLineResolver.customLines.first.mode, PlayLineMode.html);
    });

    test('删除被选为数据源的站点：自动切回官方源并解锁线路', () async {
      await PlayLineResolver.addCustom(
          name: '站点', base: 'https://x.com', mode: PlayLineMode.api);
      await SettingsService.setDataSource(
          AppConstants.dataSourceOfLine('custom-x.com'));
      await SettingsService.setPinnedLine('custom-x.com');

      await PlayLineResolver.removeCustom('custom-x.com');
      expect(SettingsService.dataSource, AppConstants.dataSourceWeb);
      expect(SettingsService.pinnedLineId, isEmpty);
    });

    test('内置站点仍可查得', () {
      expect(PlayLineResolver.byId('bsvod.com'), isNotNull);
      expect(PlayLineResolver.byId('bcvod.top'), isNotNull);
      expect(PlayLineResolver.byId('bcvod.top')!.isCustom, isFalse);
    });
  });
}
