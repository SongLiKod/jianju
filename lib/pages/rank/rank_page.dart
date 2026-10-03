import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/api_constants.dart';
import '../../core/models/drama.dart';
import '../../core/services/api_service.dart';
import '../../core/state/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/state_views.dart';
import '../detail/detail_page.dart';
import '../search/search_page.dart';

/// 排行榜：官方热度榜（总榜 / 真人榜 / 漫剧榜 / AI榜）
///
/// 1. 顶部榜单切换，展示官方更新说明
/// 2. 名次徽章 + 封面 + 标题 + 热度 + 评分 + 标签
/// 3. 下拉刷新 + 上滑分页（每页 20 条，共 5 页）
class RankPage extends StatefulWidget {
  const RankPage({super.key});

  @override
  State<RankPage> createState() => _RankPageState();
}

class _RankPageState extends State<RankPage> with AutomaticKeepAliveClientMixin {
  final List<Drama> _list = [];
  final ScrollController _scroll = ScrollController();

  String _slug = ApiConstants.rankSlugs.first;
  Map<String, String> _labels = ApiConstants.rankLabels;
  String _updatedText = '';
  bool _loading = true;
  bool _loadingMore = false;
  bool _error = false;
  bool _hasMore = false;
  int _page = 1;
  int _totalPages = 1;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _boot();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
  }

  /// 启动/重试入口：先取当前数据源的榜单 tab（站点模式为该站按热度榜单），
  /// 再拉第一页
  Future<void> _boot() async {
    try {
      final labels = await ApiService.fetchRankLabels();
      if (!mounted) return;
      if (labels.isNotEmpty) {
        setState(() {
          _labels = labels;
          if (!labels.containsKey(_slug)) _slug = labels.keys.first;
        });
      }
    } catch (e) {
      debugPrint('榜单 tab 加载失败: $e');
    }
    await _refresh();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final result = await ApiService.fetchRank(slug: _slug, page: 1);
      if (!mounted) return;
      setState(() {
        _list
          ..clear()
          ..addAll(result.items);
        _updatedText = result.updatedText;
        _totalPages = result.totalPages;
        _page = 2;
        _hasMore = result.totalPages > 1 && result.items.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      debugPrint('排行榜加载失败[$_slug]: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _list.isEmpty;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _error) return;
    if (_page > _totalPages) {
      setState(() => _hasMore = false);
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final result = await ApiService.fetchRank(slug: _slug, page: _page);
      if (!mounted) return;
      setState(() {
        final ids = _list.map((d) => d.bookId).toSet();
        for (final d in result.items) {
          if (ids.add(d.bookId)) _list.add(d);
        }
        _page++;
        _hasMore = _page <= _totalPages && result.items.isNotEmpty;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('排行榜加载更多失败[$_slug]: $e');
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _switchSlug(String slug) {
    if (slug == _slug) return;
    setState(() => _slug = slug);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final seed =
        AppPalette.colors[context.watch<ThemeProvider>().colorIndex].color;

    return Scaffold(
      appBar: AppBar(
        title: const Text('排行榜'),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _SlugBar(
            slug: _slug,
            labels: _labels,
            seed: seed,
            onChanged: _switchSlug,
          ),
          if (_updatedText.isNotEmpty) _UpdateBanner(text: _updatedText),
          Expanded(child: _buildList(context)),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (_loading && _list.isEmpty) return const LoadingView();
    if (_error) return ErrorRetryView(onRetry: _boot);
    if (_list.isEmpty) return const EmptyView(message: '榜单暂无数据');

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: 4,
          bottom: MediaQuery.paddingOf(context).bottom + 96,
        ),
        itemCount: _list.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _list.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: _loadingMore
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    )
                  : const SizedBox.shrink(),
            );
          }
          final drama = _list[index];
          return _RankTile(
            rank: index + 1,
            drama: drama,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DetailPage(bookId: drama.bookId)),
            ),
          );
        },
      ),
    );
  }
}

/// 顶部榜单切换条
class _SlugBar extends StatelessWidget {
  final String slug;
  final Map<String, String> labels;
  final Color seed;
  final ValueChanged<String> onChanged;

  const _SlugBar({
    required this.slug,
    required this.labels,
    required this.seed,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactive = isDark ? Colors.white54 : Colors.black45;
    final entries = labels.entries.toList();

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final selected = entry.key == slug;
          return ChoiceChip(
            label: Text(entry.value),
            selected: selected,
            onSelected: (_) => onChanged(entry.key),
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? seed : inactive,
            ),
            selectedColor: seed.withValues(alpha: 0.16),
            backgroundColor: isDark ? Colors.white10 : const Color(0xFFF2F2F7),
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}

/// 官方榜单更新说明
class _UpdateBanner extends StatelessWidget {
  final String text;

  const _UpdateBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.trending_up_rounded,
              size: 15, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 榜单条目：名次徽章 + 封面 + 热度/评分/标签
class _RankTile extends StatelessWidget {
  final int rank;
  final Drama drama;
  final VoidCallback onTap;

  const _RankTile({required this.rank, required this.drama, required this.onTap});

  static const _rankColors = [
    Color(0xFFFFA000), // 金
    Color(0xFF90A4AE), // 银
    Color(0xFFBF7A45), // 铜
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark ? Colors.white54 : Colors.black45;
    final top3 = rank <= 3;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 名次
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: top3
                    ? BoxDecoration(
                        color: _rankColors[rank - 1],
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: top3 ? 14 : 15,
                    fontWeight: FontWeight.w700,
                    color: top3
                        ? Colors.white
                        : isDark
                            ? Colors.white38
                            : Colors.black26,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              CoverImage(url: drama.coverUrl, width: 78, height: 104),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 104,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        drama.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 5),
                      // 热度 + 评分
                      Row(
                        children: [
                          if (drama.readCountText.isNotEmpty)
                            Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.local_fire_department_rounded,
                                      size: 15,
                                      color: theme.colorScheme.primary),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      drama.readCountText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: theme.colorScheme.primary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (drama.scoreText.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 15, color: Color(0xFFFFB300)),
                                const SizedBox(width: 2),
                                Text(
                                  drama.scoreText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFFFFB300)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        drama.abstractText.isEmpty ? '暂无简介' : drama.abstractText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: secondary, height: 1.3),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          if (drama.episodeCount > 0) ...[
                            Text('${drama.episodeCount}集',
                                style:
                                    TextStyle(fontSize: 11, color: secondary)),
                            const SizedBox(width: 8),
                          ],
                          if (drama.statusText.isNotEmpty) ...[
                            Text(drama.statusText,
                                style:
                                    TextStyle(fontSize: 11, color: secondary)),
                            const SizedBox(width: 8),
                          ],
                          if (drama.tags.isNotEmpty)
                            Flexible(
                              child: Text(
                                drama.tags.take(3).join(' / '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, color: secondary),
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
        ),
      ),
    );
  }
}
