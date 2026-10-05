import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/search_history_service.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:jianju/core/state/settings_provider.dart';
import 'package:jianju/core/state/theme_provider.dart';
import 'package:jianju/pages/search/search_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 搜索页离线行为（不发网络请求）：空态 / 历史记录 / 空关键词不触发搜索
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    SearchHistoryService.init();
    await SearchHistoryService.clear();
  });

  Future<void> pumpSearch(WidgetTester tester) async {
    final theme = ThemeProvider()..load();
    final settings = SettingsProvider()..load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ],
        child: MaterialApp(home: const SearchPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('无历史时显示空态与搜索框', (tester) async {
    await pumpSearch(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('输入关键词开始搜索'), findsOneWidget);
  });

  testWidgets('空关键词提交不触发搜索；历史记录展示与清空', (tester) async {
    await SearchHistoryService.add('庆余年');
    await pumpSearch(tester);

    // 有历史：展示关键词 chip，可重新搜索 / 删除
    expect(find.byType(InputChip), findsOneWidget);

    // 空关键词：不进入搜索态，历史照常展示
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.byType(InputChip), findsOneWidget);
    expect(find.text('搜索中...'), findsNothing);

    // 清空入口弹确认框，取消则保留
    await tester.tap(find.text('清空'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('清空搜索历史'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(InputChip), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
