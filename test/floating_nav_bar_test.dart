import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/widgets/floating_nav_bar.dart';

const _items = [
  NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: '首页'),
  NavItem(
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view,
      label: '分类'),
  NavItem(
      icon: Icons.leaderboard_outlined,
      activeIcon: Icons.leaderboard,
      label: '排行榜'),
  NavItem(
      icon: Icons.person_outline, activeIcon: Icons.person, label: '我的'),
];

/// 在指定宽度 + 字体缩放下泵出导航条。
/// 溢出（黄黑斜纹 / RenderFlex overflow）会走 FlutterError.reportError，
/// flutter_test 默认直接让用例失败，所以这里不额外断言。
Future<void> _pump(WidgetTester tester,
    {required double width, required int index, double scale = 1.0}) async {
  addTearDown(tester.view.reset);
  tester.view.physicalSize = Size(width * 3, 900);
  tester.view.devicePixelRatio = 3.0;

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      bottomNavigationBar: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 600),
          textScaler: TextScaler.linear(scale),
        ),
        child: FloatingNavBar(
          items: _items,
          currentIndex: index,
          primaryColor: Colors.blue,
          onTap: (_) {},
        ),
      ),
      body: const SizedBox.shrink(),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('底部导航条在窄屏 + 大字体下不溢出', (tester) async {
    for (final width in [320.0, 360.0, 411.0]) {
      for (final index in [0, 3]) {
        for (final scale in [1.0, 1.3, 1.5]) {
          await _pump(tester, width: width, index: index, scale: scale);
          expect(tester.takeException(), isNull,
              reason: 'w=$width index=$index scale=$scale');
        }
      }
    }
  });

  testWidgets('选中项显示文字，未选中项只显示图标', (tester) async {
    await _pump(tester, width: 360, index: 1);
    expect(find.text('分类'), findsOneWidget);
    expect(find.text('首页'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
