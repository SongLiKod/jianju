import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/state/theme_provider.dart';
import 'core/theme/app_theme.dart';
import 'pages/root_page.dart';

/// APP 根组件：主题系统挂载点
///
/// 明暗模式（浅色/深色/跟随系统）+ 自定义主色实时生效、无需重启。
class JianjuApp extends StatelessWidget {
  const JianjuApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final seed = AppPalette.colors[theme.colorIndex].color;

    return MaterialApp(
      title: '简剧',
      debugShowCheckedModeBanner: false,
      themeMode: theme.mode,
      theme: AppTheme.light(seed),
      darkTheme: AppTheme.dark(seed),
      home: const RootPage(),
    );
  }
}
