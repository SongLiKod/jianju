import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/favorite_service.dart';
import '../../core/services/history_service.dart';
import '../../core/state/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../favorites/favorites_page.dart';
import '../history/history_page.dart';

/// 我的：本地收藏 / 观看历史入口（数据仅保存在本地）
class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final seed =
        AppPalette.colors[context.watch<ThemeProvider>().colorIndex].color;
    final favCount = FavoriteService.favorites.length;
    final historyCount = HistoryService.history.length;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: EdgeInsets.only(
          top: 8,
          bottom: MediaQuery.paddingOf(context).bottom + 96,
        ),
        children: [
          // 顶部品牌区
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: seed.withValues(alpha: 0.15),
                  child:
                      Icon(Icons.play_circle_fill_rounded, color: seed, size: 32),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(AppConstants.appName,
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(AppConstants.appTagline,
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline)),
                  ],
                ),
              ],
            ),
          ),
          _Tile(
            icon: Icons.favorite_rounded,
            title: '我的收藏',
            subtitle: '$favCount 部短剧',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FavoritesPage()),
            ),
          ),
          _Tile(
            icon: Icons.history_rounded,
            title: '观看历史',
            subtitle: historyCount == 0 ? '暂无观看记录' : '共 $historyCount 条记录',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryPage()),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final seed = AppPalette.colors[context.watch<ThemeProvider>().colorIndex].color;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: ListTile(
        onTap: onTap,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: seed.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: seed, size: 21),
        ),
        title: Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(subtitle,
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38)),
        ),
        trailing: Icon(Icons.chevron_right_rounded,
            color: isDark ? Colors.white24 : Colors.black26),
      ),
    );
  }
}
