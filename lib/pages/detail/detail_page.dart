import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/drama.dart';
import '../../core/models/episode.dart';
import '../../core/models/history_entry.dart';
import '../../core/services/api_service.dart';
import '../../core/services/favorite_service.dart';
import '../../core/services/history_service.dart';
import '../../core/state/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/responsive.dart';
import '../../widgets/clickable.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/state_views.dart';
import '../player/player_page.dart';

/// 短剧详情页
/// 1. 展示短剧封面、标题、详细简介
/// 2. 展示全部分集列表
/// 3. 支持本地收藏/取消收藏（不上传服务端）
/// 4. 详情页推荐广告全部过滤（ApiService 内完成）
class DetailPage extends StatefulWidget {
  final String bookId;
  final bool autoContinue; // 从历史进入时自动续播

  const DetailPage({super.key, required this.bookId, this.autoContinue = false});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Drama? _drama;
  List<Episode> _episodes = [];
  List<Drama> _related = [];
  bool _loading = true;
  bool _error = false;
  bool _expandedAbstract = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[NAV] detail.init ${widget.bookId} auto=${widget.autoContinue}');
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final detail = await ApiService.fetchDetail(widget.bookId);
      if (!mounted) return;
      setState(() {
        _drama = detail.drama;
        _related = detail.related;
        _episodes = detail.episodes;
        _loading = false;
      });
      if (widget.autoContinue && _drama != null && _episodes.isNotEmpty) {
        final record = HistoryService.recordOf(widget.bookId);
        final index =
            record != null && record.lastEpisodeIndex > 0 ? record.lastEpisodeIndex : 1;
        final target = _episodes.where((e) => e.index == index).firstOrNull ?? _episodes.first;
        // 官方锁定集不自动续播
        if (mounted && target.playable) _play(target);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final drama = _drama;
    if (drama == null) return;
    final record = HistoryService.recordOf(drama.bookId);
    await FavoriteService.toggle(
      drama,
      episodeIndex: record?.lastEpisodeIndex ?? 1,
      episodeItemId: record?.lastEpisodeItemId ?? '',
    );
    setState(() {});
  }

  Future<void> _play(Episode episode) async {
    final drama = _drama;
    if (drama == null || !mounted) return;
    if (!episode.playable) {
      // 官方硬限制：每剧仅前 3 集免费可播
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('官方仅开放前 3 集，后续剧集暂未解锁'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // 播放前写入历史
    final record = HistoryService.recordOf(drama.bookId);
    await HistoryService.upsert(
      drama,
      episodeIndex: episode.index,
      episodeItemId: episode.itemId,
      positionMs: record?.lastEpisodeItemId == episode.itemId
          ? record?.positionMs
          : 0,
    );
    if (!mounted) return;
    debugPrint('[NAV] push player #${episode.index}');
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          drama: drama,
          episodes: _episodes,
          initialEpisode: episode,
        ),
      ),
    );
    debugPrint('[NAV] back from player');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark ? Colors.white54 : Colors.black45;
    final seed = AppPalette.colors[context.watch<ThemeProvider>().colorIndex].color;
    final record = _drama == null ? null : HistoryService.recordOf(_drama!.bookId);
    final isFav = _drama != null && FavoriteService.isFavorite(_drama!.bookId);

    return Scaffold(
      appBar: AppBar(title: const Text('短剧详情')),
      body: _loading
          ? const LoadingView()
          : _error
              ? ErrorRetryView(onRetry: _load)
              : CenteredContent(
                  child: ListView(
                    padding: EdgeInsets.only(
                      bottom:
                          AppLayout.scrollBottom(context, mobileInset: 40),
                    ),
                    children: [
                      // 宽窗口下限宽，避免头部按钮/简介被拉到 960 宽
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child:
                            _buildHeader(context, secondary, seed, isFav, record),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _buildAbstract(context, secondary, isDark),
                      ),
                      _buildEpisodeSection(context, record, secondary, isDark),
                      if (_related.isNotEmpty) ...[
                        const Divider(),
                        _buildRelated(context, secondary),
                      ],
                    ],
                  ),
                ),
    );
  }

  // ==================== 头部信息 ====================

  Widget _buildHeader(BuildContext context, Color secondary, Color seed,
      bool isFav, LocalRecord? record) {
    final drama = _drama!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverImage(url: drama.coverUrl, width: 110, height: 148),
          const SizedBox(width: 14),
          Expanded(
            child: SizedBox(
              height: 148,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drama.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700, height: 1.25),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (drama.episodeCount > 0) _chip(context, '${drama.episodeCount}集'),
                      if (drama.statusText.isNotEmpty) _chip(context, drama.statusText),
                      if (drama.readCountText.isNotEmpty) _chip(context, drama.readCountText),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      // 播放/继续播放按钮
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: seed,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            final ep =
                                _episodeByIndex(record?.lastEpisodeIndex ?? 0);
                            final target = (ep != null && ep.playable)
                                ? ep
                                : _episodes
                                    .where((e) => e.playable)
                                    .firstOrNull;
                            if (target != null) _play(target);
                          },
                          icon: Icon(
                            (record?.positionMs ?? 0) > 0
                                ? Icons.play_arrow_rounded
                                : Icons.play_circle_fill_rounded,
                            size: 20,
                          ),
                          label: Text(
                            _episodes.isEmpty
                                ? '播放'
                                : (record != null && record.lastEpisodeIndex > 0
                                    ? '继续播放 第${record.lastEpisodeIndex}集'
                                    : '立即播放 第1集'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 收藏/取消收藏
                      Clickable(
                        onTap: _toggleFavorite,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isFav
                                ? seed.withValues(alpha: 0.15)
                                : (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white10
                                    : Colors.black.withValues(alpha: 0.05)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: isFav ? seed : secondary,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, color: isDark ? Colors.white70 : Colors.black54)),
    );
  }

  // ==================== 详细简介 ====================

  Widget _buildAbstract(BuildContext context, Color secondary, bool isDark) {
    final seed = AppPalette.colors[context.watch<ThemeProvider>().colorIndex].color;
    final drama = _drama!;
    final text =
        drama.abstractText.isEmpty ? '暂无简介' : drama.abstractText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('简介',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Clickable(
            onTap: () => setState(
                () => _expandedAbstract = !_expandedAbstract),
            child: Text(
              text,
              maxLines: _expandedAbstract ? null : 3,
              overflow: _expandedAbstract ? null : TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13.5, color: secondary, height: 1.5),
            ),
          ),
          if (text.length > 60)
            Clickable(
              onTap: () => setState(
                  () => _expandedAbstract = !_expandedAbstract),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _expandedAbstract ? '收起' : '展开全部',
                  style: TextStyle(
                      fontSize: 13, color: seed, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 分集列表 ====================

  Widget _buildEpisodeSection(
      BuildContext context, LocalRecord? record, Color secondary, bool isDark) {
    if (_episodes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: EmptyView(message: '暂无分集信息'),
      );
    }
    // 分集列数随可用宽度变化：手机 4 列，桌面按宽度增列
    final screenW = MediaQuery.sizeOf(context).width;
    final contentW = AppLayout.isWide(context)
        ? (screenW - AppLayout.sidebarWidth)
            .clamp(0.0, AppLayout.contentMaxWidth)
            .toDouble()
        : screenW;
    final columns = AppLayout.columnsFor(contentW,
        targetWidth: 132, min: 4, max: 8, gutter: 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text('分集列表（共${_episodes.length}集）',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.9,
          ),
          itemCount: _episodes.length,
          itemBuilder: (context, index) {
            final ep = _episodes[index];
            final watched = record != null && ep.index < record.lastEpisodeIndex;
            final playing = record != null && ep.index == record.lastEpisodeIndex;
            final locked = !ep.playable;
            final seed = AppPalette.colors[context.watch<ThemeProvider>().colorIndex].color;
            return Material(
              color: playing
                  ? seed.withValues(alpha: 0.16)
                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.045)),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _play(ep),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (locked) ...[
                        Icon(Icons.lock_outline_rounded,
                            size: 12, color: secondary),
                        const SizedBox(width: 2),
                      ],
                      Flexible(
                        child: Text(
                          '第${ep.index}集',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight:
                                playing ? FontWeight.w700 : FontWeight.w500,
                            color: locked
                                ? secondary.withValues(alpha: 0.6)
                                : (playing
                                    ? seed
                                    : (watched ? secondary : null)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ==================== 相关推荐（已过滤广告） ====================

  Widget _buildRelated(BuildContext context, Color secondary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text('相关推荐',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _related.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final d = _related[index];
              return Clickable(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => DetailPage(bookId: d.bookId)),
                ),
                child: SizedBox(
                  width: 86,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CoverImage(url: d.coverUrl, width: 86, height: 118),
                      const SizedBox(height: 5),
                      Text(
                        d.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, height: 1.2),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Episode? _episodeByIndex(int index) {
    for (final ep in _episodes) {
      if (ep.index == index) return ep;
    }
    return null;
  }
}
