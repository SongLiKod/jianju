import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:jianju/core/state/theme_provider.dart';
import 'package:jianju/core/theme/app_theme.dart';
import 'package:jianju/widgets/brand_icon.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  testWidgets('品牌图标按主题色渲染，切色后重绘', (tester) async {
    final theme = ThemeProvider()..load();
    Widget host(int index) => MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  const BrandIcon(size: 56),
                  const BrandIcon(size: 22),
                  BrandIcon(size: 34, color: AppPalette.colors[index].color),
                ],
              ),
            ),
          ),
        );

    await tester.pumpWidget(host(0));
    expect(find.byType(BrandIcon), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    // 每个图标一枚 CustomPaint（圆角渐变底 + 三角填充 + 三角描边同层绘制）
    expect(
      find.descendant(of: find.byType(BrandIcon), matching: find.byType(CustomPaint)),
      findsNWidgets(3),
    );

    await theme.setColorIndex(7); // 清新绿
    await tester.pumpWidget(host(7));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
