import 'package:flutter/material.dart';

import '../../core/models/drama.dart';
import '../../core/services/api_service.dart';
import '../../core/services/search_history_service.dart';
import '../../widgets/drama_card.dart';
import '../../widgets/state_views.dart';
import '../detail/detail_page.dart';

/// 搜索模块
/// 1. 顶部搜索框支持关键词搜索短剧
/// 2. 搜索结果自动过滤广告条目（ApiService 内完成）
/// 3. 结果样式与首页统一，点击进入详情
/// 4. 搜索历史：点词重搜、单条删除、一键清空
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

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit([String? keyword]) async {
    final kw = (keyword ?? _controller.text).trim();
    if (kw.isEmpty || _searching) return;
    FocusScope.of(context).unfocus();
    await SearchHistoryService.add(kw);
    if (!mounted) return;
    setState(() {
      _keyword = kw;
      _searching = true;
      _error = false;
      _results.clear();
    });
    try {
      // 官方网页搜索仅返回首屏 10 条，无分页
      final items = await ApiService.search(keyword: _keyword);
      if (!mounted) return;
      setState(() {
        _results.addAll(items);
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
      body: _buildBody(),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
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
  }

  Widget _buildBody() {
    if (_searching) return const LoadingView(text: '搜索中...');
    if (_error) {
      return ErrorRetryView(
        message: '搜索失败，请稍后重试',
        onRetry: () => _submit(_keyword),
      );
    }
    if (_keyword.isEmpty) return _buildHistory();
    if (_results.isEmpty) {
      return const EmptyView(message: '没有找到相关短剧');
    }
    return ListView.builder(
      padding: EdgeInsets.only(
        top: 6,
        bottom: MediaQuery.paddingOf(context).bottom + 96,
      ),
      itemCount: _results.length + 1,
      itemBuilder: (context, index) {
        if (index >= _results.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text('仅展示前 10 条结果',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          );
        }
        final drama = _results[index];
        return DramaCard(
          drama: drama,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailPage(bookId: drama.bookId),
            ),
          ),
        );
      },
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
        bottom: MediaQuery.paddingOf(context).bottom + 96,
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
