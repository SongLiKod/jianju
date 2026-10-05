import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/state/theme_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/responsive.dart';
import 'pages/root_page.dart';

/// APP 根组件：主题系统挂载点
///
/// 明暗模式（浅色/深色/跟随系统）+ 自定义主色实时生效、无需重启；
/// 主题随窗口宽度切换桌面/移动形态（标题对齐方式、分割线等）。
class JianjuApp extends StatelessWidget {
  const JianjuApp({super.key});

  /// 全局路由句柄：MaterialApp.builder 的 context 在 Navigator 之上，
  /// Esc 回退只能通过它取到路由栈
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final seed = AppPalette.colors[theme.colorIndex].color;

    // 此处位于 MaterialApp 之上（尚无 MediaQuery），用窗口约束判定宽窄
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final wide = width.isFinite && width >= AppLayout.wideBreakpoint;

      return MaterialApp(
        title: AppConstants.appName,
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        themeMode: theme.mode,
        theme: AppTheme.light(seed, wide: wide),
        darkTheme: AppTheme.dark(seed, wide: wide),
        home: const RootPage(),
        // 桌面端惯例：Esc 返回上一页（弹窗走 barrier 自带逻辑，
        // 播放页在其路由内绑定 Esc，优先级高于本全局绑定）
        builder: (context, child) {
          final Widget subtree = child ?? const SizedBox.shrink();
          if (defaultTargetPlatform == TargetPlatform.android) return subtree;
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  navigatorKey.currentState?.maybePop(),
            },
            child: subtree,
          );
        },
      );
    });
  }
}
