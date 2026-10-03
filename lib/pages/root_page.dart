import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/state/settings_provider.dart';
import '../core/state/theme_provider.dart';
import '../core/theme/app_theme.dart';
import '../widgets/floating_nav_bar.dart';
import 'category/category_page.dart';
import 'home/home_page.dart';
import 'mine/mine_page.dart';
import 'rank/rank_page.dart';

/// 主框架：四个 Tab + 苹果风格悬浮导航条
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;

  static const _navItems = [
    NavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: '首页'),
    NavItem(icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view_rounded, label: '分类'),
    NavItem(icon: Icons.leaderboard_outlined, activeIcon: Icons.leaderboard_rounded, label: '排行榜'),
    NavItem(icon: Icons.favorite_border_rounded, activeIcon: Icons.favorite_rounded, label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = context.watch<ThemeProvider>();
    final source = context.watch<SettingsProvider>().dataSource;
    final seed = AppPalette.colors[primary.colorIndex].color;
    return Scaffold(
      extendBody: true,
      // 数据源切换后整树重建：四个 Tab 全部按新站点重新拉数据
      body: IndexedStack(
        key: ValueKey(source),
        index: _index,
        children: const [
          HomePage(),
          CategoryPage(),
          RankPage(),
          MinePage(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: FloatingNavBar(
            items: _navItems,
            currentIndex: _index,
            primaryColor: seed,
            onTap: (i) => setState(() => _index = i),
          ),
        ),
      ),
    );
  }
}
