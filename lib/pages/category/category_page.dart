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

/// 分类页：按内容类型（真人剧 / 漫剧 / AI短剧 / 动态漫）浏览短剧
///
/// 1. 顶部类型切换，切换后重新拉取
/// 2. 网格瀑布展示封面、标题、集数、状态
/// 3. 下拉刷新 + 上滑分页（官方每页 24 条，共 34 页）
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage>
    with AutomaticKeepAliveClientMixin {
  final List<Drama> _list = [];
  final ScrollController _scroll = ScrollController();

  String _slug = ApiConstants.categorySlugs.first;
  Map<String, String> _labels = ApiConstants.categoryLabels;
  bool _loading = true;
  bool _loadingMore = false;
  bool _error = false;
  bool _hasMore = true;
  int _page = 1;

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

  /// 启动/重试入口：先取当前数据源的分类 tab（站点模式为该站全站分类），
  /// 再拉第一页内容
  Future<void> _boot() async {
    try {
      final labels = await ApiService.fetchCategoryLabels();
      if (!mounted) return;
      if (labels.isNotEmpty) {
        setState(() {
          _labels = labels;
          if (!labels.containsKey(_slug)) _slug = labels.keys.first;
        });
      }
    } catch (e) {
      debugPrint('分类 tab 加载失败: $e');
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
      final items = await ApiService.fetchCategory(slug: _slug, page: 1);
      if (!mounted) return;
      setState(() {
        _list
          ..clear()
          ..addAll(items);
        _page = 2;
        _hasMore = items.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      debugPrint('分类加载失败[$_slug]: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _list.isEmpty;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _error) return;
    setState(() => _loadingMore = true);
    try {
      final items = await ApiService.fetchCategory(slug: _slug, page: _page);
      if (!mounted) return;
      setState(() {
        final ids = _list.map((d) => d.bookId).toSet();
        for (final d in items) {
          if (ids.add(d.bookId)) _list.add(d);
        }
        _page++;
        _hasMore = items.isNotEmpty;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('分类加载更多失败[$_slug]: $e');
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
        title: const Text('分类'),
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
          Expanded(child: _buildGrid(context)),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    if (_loading && _list.isEmpty) return const LoadingView();
    if (_error) return ErrorRetryView(onRetry: _boot);
    if (_list.isEmpty) return const EmptyView(message: '该分类暂无内容');

    return RefreshIndicator(
      onRefresh: _refresh,
      child: GridView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          MediaQuery.paddingOf(context).bottom + 96,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 14,
          crossAxisSpacing: 10,
          childAspectRatio: 0.58,
        ),
        itemCount: _list.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _list.length) {
            return Center(
              child: _loadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const SizedBox.shrink(),
            );
          }
          final drama = _list[index];
          return _GridItem(drama: drama, onTap: () => _openDetail(drama));
        },
      ),
    );
  }

  void _openDetail(Drama drama) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailPage(bookId: drama.bookId)),
    );
  }
}

/// 顶部内容类型切换条
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

/// 网格卡片：封面 + 标题 + 集数/状态（热度有值时一并展示）
class _GridItem extends StatelessWidget {
  final Drama drama;
  final VoidCallback onTap;

  const _GridItem({required this.drama, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark ? Colors.white54 : Colors.black45;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: CoverImage(
              url: drama.coverUrl,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            drama.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              if (drama.readCountText.isNotEmpty) ...[
                Icon(Icons.local_fire_department_rounded,
                    size: 12, color: theme.colorScheme.primary),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    drama.readCountText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: theme.colorScheme.primary),
                  ),
                ),
              ] else if (drama.statusText.isNotEmpty) ...[
                Flexible(
                  child: Text(
                    drama.statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: secondary),
                  ),
                ),
              ] else if (drama.episodeCount > 0) ...[
                Flexible(
                  child: Text(
                    '${drama.episodeCount}集',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: secondary),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
