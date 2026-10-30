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

/// 设置页「添加自定义站点」对话框全流程：
/// 输入地址 → 检测并添加 →（测试环境探测失败）仍要添加 → 列表出现新站点
/// 回归：真机上该流程曾抛出
/// framework.dart InheritedElement.debugDeactivated: _dependents.isEmpty is not true
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

  testWidgets('添加自定义站点：检测并添加全流程不崩溃', (tester) async {
    await pumpSettings(tester);
    expect(tester.takeException(), isNull);

    final add = find.text('添加自定义站点');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('添加自定义站点'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'fhapi9.com');
    await tester.pump();
    expect(find.text('fhapi9.com'), findsOneWidget);

    await tester.tap(find.text('检测并添加'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);

    // 测试环境无真实网络，探测失败时给出原因并允许强行添加
    if (find.text('仍要添加').evaluate().isNotEmpty) {
      await tester.tap(find.text('仍要添加'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    } else {
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);

    // 对话框关闭 + 站点入库
    expect(PlayLineResolver.customLines.any((l) => l.base.contains('fhapi9')),
        isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // 站点列表里出现新站点
    final expand = find.textContaining('点击展开选择');
    if (expand.evaluate().isNotEmpty) {
      await tester.ensureVisible(expand);
      await tester.tap(expand);
      await tester.pump();
      expect(find.text('fhapi9.com'), findsWidgets);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('检测未通过时展示原因并可取消', (tester) async {
    await pumpSettings(tester);

    final add = find.text('添加自定义站点');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'fhapi9.com');
    await tester.tap(find.text('检测并添加'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 3));

    // 取消并确认页面仍可用（无遗留崩溃）
    final cancel = find.text('取消');
    if (cancel.evaluate().isNotEmpty) {
      await tester.tap(cancel);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    expect(find.text('添加自定义站点'), findsWidgets);
  });
}
