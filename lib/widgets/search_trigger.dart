import 'package:flutter/material.dart';

import '../pages/search/search_page.dart';

/// 宽窗口顶栏的搜索入口：外观做成输入框，点击（或 Ctrl+F）进入搜索页
class SearchTrigger extends StatelessWidget {
  final double width;

  const SearchTrigger({super.key, this.width = 280});

  void _open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SearchPage()),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hint = Theme.of(context).colorScheme.outline;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(context),
        child: Tooltip(
          message: '搜索短剧（Ctrl+F）',
          child: Container(
            width: width,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 17, color: hint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '搜索短剧',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: hint),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'Ctrl F',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: hint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
