import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/drama.dart';
import '../../core/services/api_service.dart';
import '../../core/services/play_lines.dart';
import '../../core/services/search_history_service.dart';
import '../../core/services/source_label.dart';
import '../../core/state/settings_provider.dart';
import '../../core/theme/responsive.dart';
import '../../widgets/drama_card.dart';
import '../../widgets/poster_card.dart';
import '../../widgets/state_views.dart';
import '../detail/detail_page.dart';

/// 搜索模块
/// 1. 顶部搜索框支持关键词搜索短剧
/// 2. 搜索范围可切换：跨站（默认）/ 本站 / 指定站点（见 AppConstants.searchScope*）
/// 3. 跨站聚合搜索：当前源 + 官方源 + 52api + 全部启用中的整站站点并发查询
/// 4. 展示条数可在 设置 → 搜索 → 搜索结果条数 里配置（默认 10 条）
/// 5. 搜索结果自动过滤广告条目（ApiService 内完成）
/// 6. 结果样式与首页统一，点击进入详情
/// 7. 搜索历史：点词重搜、单条删除、一键清空
/// 8. 宽窗口下结果切换为海报网格，搜索框限宽左对齐
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final List<Drama> _results = [];

  bool _searching = false;
  bool _error = false;
  String _keyword = '';

  /// 跨站搜索进度：已完成站点数 / 总站点数
  int _done = 0;
  int _total = 0;

  /// 本次搜索采用的结果条数上限（设置 → 搜索）
  int _limit = AppConstants.defaultSearchLimit;

  /// 搜索范围：跨站 / 本站 / 指定站点（首次 build 时从设置读入）
  String _scope = AppConstants.defaultSearchScope;

  /// 「指定站点」勾选的站点 id
  final Set<String> _picked = <String>{};
  bool _scopeLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scopeLoaded) return;
    _scopeLoaded = true;
    final s = context.read<SettingsProvider>();
    _scope = s.searchScope;
    _picked
      ..clear()
      ..addAll(s.pickedSites);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit([String? keyword]) async {
    final kw = (keyword ?? _controller.text).trim();
    if (kw.isEmpty || _searching) return;
    // 指定站点模式下没勾选任何站点：先弹选择器，不发起搜索
    if (_scope == AppConstants.searchScopePicked && _picked.isEmpty) {
      await _pickSites();
      if (_picked.isEmpty || !mounted) return;
    }
    FocusScope.of(context).unfocus();
    await SearchHistoryService.add(kw);
    if (!mounted) return;
    final limit = context.read<SettingsProvider>().searchLimit;
    final scope = _scope;
    setState(() {
      _keyword = kw;
      _searching = true;
      _error = false;
      _results.clear();
      _done = 0;
      _total = 0;
      _limit = limit;
    });
    try {
      final List<Drama> items;
      if (scope == AppConstants.searchScopeLocal) {
        // 本站：只查当前数据源，无跨站进度
        items = await ApiService.search(keyword: kw);
        if (!mounted) return;
        setState(() {
          _results
            ..clear()
            ..addAll(items);
          _searching = false;
          _total = 1;
          _done = 1;
        });
        return;
      }
      // 并发搜索：站点陆续返回，结果边搜边出
      items = await ApiService.searchAcross(
        keyword: kw,
        limit: limit,
        onlyIds: scope == AppConstants.searchScopePicked
            ? Set<String>.of(_picked)
            : null,
        onUpdate: (merged, done, total) {
          if (!mounted) return;
          setState(() {
            _results
              ..clear()
              ..addAll(merged);
            _done = done;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _results
          ..clear()
          ..addAll(items);
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: _buildSearchBar(context),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: Column(
        children: [
          _scopeBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  // ==================== 搜索范围（跨站 / 本站 / 指定站点） ====================

  /// 搜索范围选择条：始终显示，切换后立即按新范围重搜
  Widget _scopeBar() {
    final scheme = Theme.of(context).colorScheme;
    final outline = scheme.outline;

    Widget chip(String value, String label, {String? badge}) {
      final selected = _scope == value;
      return ChoiceChip(
        label: Text(
          badge == null ? label : '$label·$badge',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.onPrimaryContainer : outline,
          ),
        ),
        selected: selected,
        selectedColor: scheme.primaryContainer,
        visualDensity: VisualDensity.compact,
        showCheckmark: false,
        onSelected: (_) => _selectScope(value),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 2),
      child: Row(
        children: [
          chip(AppConstants.searchScopeCross, '跨站'),
          const SizedBox(width: 6),
          chip(AppConstants.searchScopeLocal, '本站'),
          const SizedBox(width: 6),
          chip(
            AppConstants.searchScopePicked,
            '指定站点',
            badge: _picked.isEmpty ? null : '${_picked.length}',
          ),
          const Spacer(),
          if (_scope == AppConstants.searchScopePicked)
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: scheme.primary,
              ),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('选择', style: TextStyle(fontSize: 13)),
              onPressed: _pickSites,
            ),
        ],
      ),
    );
  }

  /// 切换搜索范围：持久化到设置，并按新范围重搜当前关键词
  Future<void> _selectScope(String value) async {
    if (_scope == value) {
      if (value == AppConstants.searchScopePicked) await _pickSites();
      return;
    }
    setState(() => _scope = value);
    await context.read<SettingsProvider>().setSearchScope(value);
    if (value == AppConstants.searchScopePicked && _picked.isEmpty) {
      await _pickSites();
    }
    if (!mounted || _keyword.isEmpty || _searching) return;
    await _submit(_keyword);
  }

  /// 勾选「指定站点」搜索的目标（官方源 / 52api / 启用中的整站站点）
  Future<void> _pickSites() async {
    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    final options = <({String id, String label})>[
      (id: AppConstants.dataSourceWeb, label: '官方网页源'),
      if (settings.hasApi52Key)
        (id: AppConstants.dataSourceApi52, label: '52api 聚合源'),
      for (final line in PlayLineResolver.enabledLines)
        (id: line.id, label: line.name),
    ];
    var picked = Set<String>.of(_picked);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('选择搜索站点', style: TextStyle(fontSize: 17)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final opt in options)
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: Text(opt.label,
                        style: const TextStyle(fontSize: 14)),
                    value: picked.contains(opt.id),
                    onChanged: (v) => setDialogState(() {
                      if (v == true) {
                        picked.add(opt.id);
                      } else {
                        picked.remove(opt.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setDialogState(() => picked = <String>{}),
              child: const Text('清空'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _picked
      ..clear()
      ..addAll(picked));
    await context.read<SettingsProvider>().setPickedSites(_picked);
    if (!mounted) return;
    if (_keyword.isNotEmpty && !_searching) await _submit(_keyword);
  }

  Widget _buildSearchBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final field = TextField(
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onSubmitted: _submit,
      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1C1C1E)),
      decoration: InputDecoration(
        hintText: '搜索短剧名称 / 关键词',
        hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 38, minHeight: 20),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.cancel_rounded,
                    size: 18,
                    color: isDark ? Colors.white30 : Colors.black26),
                onPressed: () {
                  _controller.clear();
                  setState(() {
                    _keyword = '';
                    _results.clear();
                    _error = false;
                  });
                },
              ),
        isDense: true,
      ),
      onChanged: (_) => setState(() {}),
    );
    // 宽窗口下搜索框限宽，避免占满整条顶栏
    if (!AppLayout.isWide(context)) return field;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: field,
    );
  }

  Widget _buildBody() {
    if (_error && _results.isEmpty) {
      return ErrorRetryView(
        message: '搜索失败，请稍后重试',
        onRetry: () => _submit(_keyword),
      );
    }
    if (_keyword.isEmpty) return _buildHistory();
    if (_results.isEmpty) {
      return LoadingView(text: _searching ? '搜索中...' : '没有找到相关短剧');
    }
    if (AppLayout.isWide(context)) return _buildWideResults(context);
    return ListView.builder(
      padding: EdgeInsets.only(
        top: 6,
        bottom: AppLayout.scrollBottom(context),
      ),
      itemCount: _results.length + 1,
      itemBuilder: (context, index) {
        if (index >= _results.length) return _footer();
        final drama = _results[index];
        return DramaCard(
          drama: drama,
          sourceLabel: SourceLabel.of(drama.bookId),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailPage(bookId: drama.bookId),
            ),
          ),
        );
      },
    );
  }

  /// 结果列表底部：搜索进度 / 展示条数说明
  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          _footerText(),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }

  String _footerText() {
    if (_scope == AppConstants.searchScopeLocal) {
      if (_searching) return '正在本站搜索…';
      return '本站搜索 · 共 ${_results.length} 条';
    }
    final unit =
        _scope == AppConstants.searchScopePicked ? '指定站点' : '跨站';
    if (_searching && _total > 0) {
      return '正在$unit搜索 $_done/$_total 个站点 · 已返回 ${_results.length} 条';
    }
    if (_searching) return '正在$unit搜索…';
    if (_results.length >= _limit) {
      return '已搜索 $_total 个站点 · 仅展示前 $_limit 条（可在设置中调整）';
    }
    return '已搜索 $_total 个站点 · 共 ${_results.length} 条';
  }

  /// 宽窗口：搜索结果以海报网格展示
  Widget _buildWideResults(BuildContext context) {
    return Column(
      children: [
        if (_searching && _total > 0)
          LinearProgressIndicator(
            value: _done / (_total == 0 ? 1 : _total),
            minHeight: 2,
            backgroundColor: Colors.transparent,
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = AppLayout.columnsFor(
                constraints.maxWidth,
                targetWidth: 176,
                min: 3,
                max: 8,
                gutter: AppLayout.wideGutter,
              );
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                    AppLayout.wideGutter, 8, AppLayout.wideGutter, 0),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 22,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.64,
                ),
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final drama = _results[index];
                  return PosterCard(
                    drama: drama,
                    sourceLabel: SourceLabel.of(drama.bookId),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DetailPage(bookId: drama.bookId),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 24, top: 4),
          child: Text(
            _footerText(),
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ],
    );
  }

  // ==================== 搜索历史 ====================

  Widget _buildHistory() {
    final items = SearchHistoryService.items;
    if (items.isEmpty) {
      return const EmptyView(message: '输入关键词开始搜索');
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: EdgeInsets.only(
        top: 10,
        left: 16,
        right: 16,
        bottom: AppLayout.scrollBottom(context),
      ),
      children: [
        Row(
          children: [
            Text('搜索历史',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.outline)),
            const Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: Colors.redAccent.withValues(alpha: 0.9),
              ),
              icon: const Icon(Icons.delete_sweep_outlined, size: 17),
              label: const Text('清空', style: TextStyle(fontSize: 13)),
              onPressed: _clearHistory,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kw in items)
              InputChip(
                label: Text(kw, style: const TextStyle(fontSize: 13)),
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05),
                deleteIconColor: isDark ? Colors.white38 : Colors.black38,
                onPressed: () {
                  _controller.text = kw;
                  _submit(kw);
                },
                onDeleted: () async {
                  await SearchHistoryService.remove(kw);
                  debugPrint('[SEARCH] history removed: $kw');
                  if (mounted) setState(() {});
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text('点击关键词重新搜索，点 × 删除单条',
            style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 4),
      ],
    );
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空搜索历史', style: TextStyle(fontSize: 17)),
        content: const Text('将删除全部搜索历史记录，确定清空吗？',
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
    await SearchHistoryService.clear();
    debugPrint('[SEARCH] history cleared');
    if (mounted) setState(() {});
  }
}
