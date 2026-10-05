import 'package:flutter/material.dart';

import '../../core/models/history_entry.dart';
import '../../core/services/history_service.dart';
import '../../core/theme/responsive.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/state_views.dart';
import '../detail/detail_page.dart';

/// 观看历史列表（本地数据，含播放进度）
/// 支持单条删除（点删除按钮/左滑）与清空全部
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  Widget build(BuildContext context) {
    final history = HistoryService.history;
    return Scaffold(
      appBar: AppBar(
        title: const Text('观看历史'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              tooltip: '清空记录',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: CenteredContent(
        child: history.isEmpty
            ? const EmptyView(message: '暂无观看记录')
            : ListView.separated(
                padding: EdgeInsets.only(
                  top: 6,
                  bottom: AppLayout.scrollBottom(context, mobileInset: 32),
                ),
                itemCount: history.length,
                separatorBuilder: (_, _) => const Divider(indent: 76),
                itemBuilder: (context, index) {
                  final record = history[index];
                  return Dismissible(
                    key: ValueKey('history-${record.drama.bookId}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.redAccent,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: Colors.white),
                    ),
                    onDismissed: (_) async {
                      await HistoryService.remove(record.drama.bookId);
                      debugPrint(
                          '[HIS] swiped removed ${record.drama.bookId}');
                      if (mounted) setState(() {});
                    },
                    child: _buildItem(context, record),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空观看历史', style: TextStyle(fontSize: 17)),
        content: const Text('将删除全部观看记录与进度记忆，确定清空吗？',
            style: TextStyle(fontSize: 14)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    await HistoryService.clear();
    debugPrint('[HIS] cleared');
    if (mounted) setState(() {});
  }

  Future<void> _removeOne(String bookId) async {
    await HistoryService.remove(bookId);
    debugPrint('[HIS] removed $bookId');
    if (mounted) setState(() {});
  }

  Widget _buildItem(BuildContext context, LocalRecord record) {
    final drama = record.drama;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark ? Colors.white54 : Colors.black45;
    final progressText = record.positionMs > 0 ? '看到第${record.lastEpisodeIndex}集' : '看过第${record.lastEpisodeIndex}集';

    return ListTile(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetailPage(bookId: drama.bookId, autoContinue: true),
          ),
        );
        if (mounted) setState(() {});
      },
      contentPadding: const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 4),
      leading: CoverImage(url: drama.coverUrl, width: 52, height: 70),
      title: Text(
        drama.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(progressText, style: TextStyle(fontSize: 12, color: secondary)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '删除该条',
            icon: Icon(Icons.delete_outline_rounded,
                size: 20, color: isDark ? Colors.white38 : Colors.black38),
            onPressed: () => _removeOne(drama.bookId),
          ),
          Icon(Icons.chevron_right_rounded,
              color: isDark ? Colors.white24 : Colors.black26),
        ],
      ),
    );
  }
}
