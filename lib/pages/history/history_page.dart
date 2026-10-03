import 'package:flutter/material.dart';

import '../../core/models/history_entry.dart';
import '../../core/services/history_service.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/state_views.dart';
import '../detail/detail_page.dart';

/// 观看历史列表（本地数据，含播放进度）
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
      appBar: AppBar(title: const Text('观看历史')),
      body: history.isEmpty
          ? const EmptyView(message: '暂无观看记录')
          : ListView.separated(
              padding: EdgeInsets.only(
                top: 6,
                bottom: MediaQuery.paddingOf(context).bottom + 32,
              ),
              itemCount: history.length,
              separatorBuilder: (_, _) => const Divider(indent: 76),
              itemBuilder: (context, index) {
                return _buildItem(context, history[index]);
              },
            ),
    );
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      trailing: Icon(Icons.chevron_right_rounded,
          color: isDark ? Colors.white24 : Colors.black26),
    );
  }
}
