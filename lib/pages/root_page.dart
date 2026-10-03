import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/state/theme_provider.dart';
import '../core/theme/app_theme.dart';
import '../widgets/floating_nav_bar.dart';
import 'home/home_page.dart';
import 'mine/mine_page.dart';
import 'search/search_page.dart';
import 'settings/settings_page.dart';

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
    NavItem(icon: Icons.search_outlined, activeIcon: Icons.search_rounded, label: '搜索'),
    NavItem(icon: Icons.favorite_border_rounded, activeIcon: Icons.favorite_rounded, label: '我的'),
    NavItem(icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = context.watch<ThemeProvider>();
    final seed = AppPalette.colors[primary.colorIndex].color;
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: const [
          HomePage(),
          SearchPage(),
          MinePage(),
          SettingsPage(),
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
