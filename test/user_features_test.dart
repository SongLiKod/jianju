import 'dart:io';

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

    test('非法存储值回退默认（超出钳制范围）', () async {
      await SettingsService.setPreloadLeadSec(7); // 不在 [5,10,15,30,60]
      expect(SettingsService.preloadLeadSec, AppConstants.defaultPreloadLeadSec);

      // 缓冲秒数做范围钳制（1~3600）而非列表校验：
      // 自定义分钟数（60~3600，如 5 分钟=300）必须持久化，重启不丢
      await SettingsService.setBufferSecs(300);
      expect(SettingsService.bufferSecs, 300);
      await SettingsService.setBufferSecs(0);
      expect(SettingsService.bufferSecs, AppConstants.defaultBufferSecs);
      await SettingsService.setBufferSecs(99999);
      expect(SettingsService.bufferSecs, AppConstants.defaultBufferSecs);
    });
  });

  // ==================== 清晰度增强开关（路径 A；路径 B 已移除） ====================

  group('清晰度增强开关', () {
    test('默认值：选线开关开', () {
      final p = SettingsProvider()..load();
      expect(p.lineQualityFirst, isTrue);
      expect(SettingsService.lineQualityFirst, isTrue);
    });

    test('修改后立即生效并持久化，重开 app 仍是修改值', () async {
      final p = SettingsProvider()..load();
      await p.setLineQualityFirst(false);
      expect(p.lineQualityFirst, isFalse);

      final fresh = SettingsProvider()..load();
      expect(fresh.lineQualityFirst, isFalse);
      expect(SettingsService.lineQualityFirst, isFalse);
    });

    test('存储缺失回退默认；按 \'1\' 布尔格式解析', () async {
      expect(SettingsService.lineQualityFirst,
          AppConstants.defaultLineQualityFirst);

      await StorageService.setString(AppConstants.keyLineQualityFirst, '0');
      expect(SettingsService.lineQualityFirst, isFalse);

      await StorageService.setString(AppConstants.keyLineQualityFirst, '');
      expect(SettingsService.lineQualityFirst,
          AppConstants.defaultLineQualityFirst);
    });

    test('路径 B 已整体移除：源码中不再出现高画质渲染相关键位', () {
      final src = File('lib/core/constants/app_constants.dart').readAsStringSync();
      expect(src.contains('render_quality'), isFalse);
      final svc = File('lib/core/services/settings_service.dart').readAsStringSync();
      expect(svc.contains('renderQuality'), isFalse);
      final ui = File('lib/pages/settings/settings_page.dart').readAsStringSync();
      expect(ui.contains('renderQuality'), isFalse);
    });
  });

  // ==================== 搜索结果条数 ====================

  group('搜索结果条数', () {
    test('默认 10 条，修改后立即生效并持久化', () async {
      final p = SettingsProvider()..load();
      expect(p.searchLimit, AppConstants.defaultSearchLimit);
      expect(p.searchLimit, 10);

      await p.setSearchLimit(30);
      expect(p.searchLimit, 30);
      final fresh = SettingsProvider()..load();
      expect(fresh.searchLimit, 30);
    });

    test('非法存储值回退默认（不在候选项里）', () async {
      await SettingsService.setSearchLimit(99);
      expect(SettingsService.searchLimit, AppConstants.defaultSearchLimit);
      await SettingsService.setSearchLimit(10);
      expect(SettingsService.searchLimit, 10);
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
