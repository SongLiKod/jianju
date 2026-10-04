import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/drama.dart';
import '../../core/services/api_service.dart';
import '../../core/services/play_lines.dart';
import '../../core/state/settings_provider.dart';
import '../../core/state/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/drama_card.dart';
import '../../widgets/state_views.dart';
import '../detail/detail_page.dart';
import '../search/search_page.dart';

/// 首页：推荐信息流
/// 1. 拉取红果短剧官方首页分区推荐 + 分类分页
/// 2. 网页源无广告卡片，纯净展示正规短剧
/// 3. 下拉分页加载更多短剧
/// 4. 展示封面、标题、简介、集数、热度
/// 5. 点击卡片进入短剧详情页
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  final List<Drama> _list = [];
  final ScrollController _scroll = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _error = false;
  bool _hasMore = true;
  int _page = 0;
  int _seq = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    // 初始加载/下拉刷新/失败重试共用；首次加载时 _loading 已为 true
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = false;
      _loadingMore = false;
    });
    try {
      final items = await ApiService.fetchHomeFeed(page: 0);
      if (!mounted || seq != _seq) return;
      debugPrint('首页推荐加载: ${items.length} 条');
      setState(() {
        _list
          ..clear()
          ..addAll(items);
        _page = 1;
        _hasMore = true;
        _loading = false;
      });
    } catch (e) {
      debugPrint('首页推荐加载失败: $e');
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = _list.isEmpty;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _error) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final items = await ApiService.fetchHomeFeed(page: _page);
      if (!mounted || seq != _seq) return;
      setState(() {
        // 去重（信息流可能重复推荐）
        final ids = _list.map((d) => d.bookId).toSet();
        for (final d in items) {
          if (ids.add(d.bookId)) _list.add(d);
        }
        _page++;
        _hasMore = items.isNotEmpty;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('首页加载更多失败: $e');
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  bool _switchDataSource(String v) {
    final provider = context.read<SettingsProvider>();
    if (v == AppConstants.dataSourceApi52 && !provider.hasApi52Key) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('52api 红果源需先在「设置」中配置 apikey'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
    provider.setDataSource(v);
    return true;
  }

  /// 数据源切换底部弹层：官方源 + 整站线路分组展示，当前项高亮打勾
  void _showSourceSheet() {
    final current = context.read<SettingsProvider>().dataSource;
    final seed =
        AppPalette.colors[context.read<ThemeProvider>().colorIndex].color;
    final outline = Theme.of(context).colorScheme.outline;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        Widget row(String value, String label, String? desc, IconData icon) {
          final selected = value == current;
          return ListTile(
            dense: true,
            leading: Icon(icon,
                size: 22, color: selected ? seed : outline),
            title: Text(label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? seed : null)),
            subtitle: desc == null
                ? null
                : Text(desc,
                    style: TextStyle(fontSize: 12, color: outline)),
            trailing: selected
                ? Icon(Icons.check_rounded, color: seed, size: 20)
                : null,
            onTap: () {
              if (_switchDataSource(value)) {
                Navigator.pop(sheetContext);
              }
            },
          );
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('切换数据源',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: seed)),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      row(
                          AppConstants.dataSourceWeb,
                          '官方网页源',
                          '红果官网 · 免配置 · 前 3 集可播',
                          Icons.language_rounded),
                      const Divider(indent: 16),
                      row(
                          AppConstants.dataSourceApi52,
                          '52api 红果源',
                          '全集可播 · 需 apikey',
                          Icons.cloud_outlined),
                      for (final line in PlayLineResolver.allLines)
                        if (line.mode == PlayLineMode.api) ...[
                          const Divider(indent: 16),
                          row(
                              AppConstants.dataSourceOfLine(line.id),
                              line.name,
                              Uri.tryParse(line.base)?.host,
                              Icons.dns_outlined),
                        ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final seed = AppPalette.colors[context.watch<ThemeProvider>().colorIndex].color;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_fill_rounded, color: seed, size: 22),
            const SizedBox(width: 6),
            const Text('简剧'),
          ],
        ),
        actions: [
          // 数据源/站点切换：整站模式下首页、分类、榜单、搜索全部跟随所选站点
          IconButton(
            tooltip: '切换数据源',
            icon: const Icon(Icons.dns_outlined),
            onPressed: _showSourceSheet,
          ),
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchPage()),
            ),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _list.isEmpty) return const LoadingView();
    if (_error) {
      return ErrorRetryView(onRetry: _refresh);
    }
    if (_list.isEmpty) {
      return const EmptyView(message: '暂无推荐内容');
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        // 底部留出悬浮导航条空间
        padding: EdgeInsets.only(
          top: 6,
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
          return DramaCard(
            drama: drama,
            onTap: () => _openDetail(drama),
          );
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
