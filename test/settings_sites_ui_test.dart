import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/play_lines.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:jianju/core/state/settings_provider.dart';
import 'package:jianju/core/state/theme_provider.dart';
import 'package:jianju/pages/settings/settings_page.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置页「整站站点」模块：默认折叠不铺开站点，展开后可按名称筛选
class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    PathProviderPlatform.instance = _FakePathProvider();
    PlayLineResolver.resetCustomLinesForTest();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    // 放大视口让整页一次建出来，避免 ListView 懒建导致找不到未滚动到的项
    await tester.binding.setSurfaceSize(const Size(800, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final theme = ThemeProvider()..load();
    final settings = SettingsProvider()..load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ],
        child: MaterialApp(home: const SettingsPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
  }

  int apiSiteCount() => PlayLineResolver.allLines
      .where((l) => !l.isCustom && l.mode == PlayLineMode.api)
      .length;

  testWidgets('整站站点默认折叠：只显示当前站点与总数', (tester) async {
    await pumpSettings(tester);
    expect(tester.takeException(), isNull);

    final total = apiSiteCount() + PlayLineResolver.customLines.length;
    expect(find.textContaining('共 $total 个站点'), findsWidgets);
    expect(find.text('添加自定义站点'), findsWidgets);
    expect(find.text('bsvod.com'), findsNothing); // 折叠态不铺开站点
    expect(find.text('收起站点列表'), findsNothing);

    // 搜索结果条数设置项（默认 10 条）
    expect(find.text('搜索结果条数'), findsWidgets);
    expect(find.text('10 条'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开后列出全部站点，可筛选与收起', (tester) async {
    await pumpSettings(tester);

    final expand = find.textContaining('点击展开选择');
    await tester.ensureVisible(expand);
    await tester.tap(expand);
    await tester.pump();

    expect(find.text('bsvod.com'), findsWidgets);
    expect(find.text('bhvod.com'), findsWidgets);
    expect(find.text('收起站点列表'), findsWidgets);
    expect(find.text('添加自定义站点'), findsWidgets);

    // 筛选：只剩匹配项
    final filter = find.byType(TextField).first;
    await tester.ensureVisible(filter);
    await tester.enterText(filter, 'bhvod');
    await tester.pump();
    expect(find.text('bhvod.com'), findsWidgets);
    expect(find.text('bsvod.com'), findsNothing);

    // 清空筛选后仍列出全部
    await tester.enterText(filter, '');
    await tester.pump();
    expect(find.text('bsvod.com'), findsWidgets);

    final collapse = find.text('收起站点列表');
    await tester.ensureVisible(collapse);
    await tester.tap(collapse);
    await tester.pump();
    expect(find.text('bsvod.com'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
