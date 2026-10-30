import 'package:flutter/material.dart';

import '../../core/services/play_lines.dart';
import '../../core/services/site_discovery_service.dart';
import '../../core/theme/responsive.dart';
import '../../widgets/state_views.dart';

/// 在线发现资源站
///
/// 从公网查找候选资源站 / API（搜索引擎结果页、GitHub 仓库搜索、
/// 可用站点友链三个来源），逐个探测可用性后由用户勾选确认，
/// 写入自定义站点库即可参与整站源与跨站搜索。
///
/// 也支持粘贴订阅地址导入候选（同样先探测再确认）；
/// **不内置任何默认订阅地址**，站点库的种子一律来自当次联网查找。
class SiteDiscoveryPage extends StatefulWidget {
  const SiteDiscoveryPage({super.key});

  @override
  State<SiteDiscoveryPage> createState() => _SiteDiscoveryPageState();
}

class _SiteDiscoveryPageState extends State<SiteDiscoveryPage> {
  final TextEditingController _kwCtrl = TextEditingController(text: '短剧');
  final TextEditingController _importCtrl = TextEditingController();

  bool _useEngine = true;
  bool _useGithub = true;
  bool _useFriend = true;

  bool _running = false;
  bool _importing = false;

  List<SiteCandidate> _candidates = [];
  final List<String> _notes = [];

  @override
  void dispose() {
    _kwCtrl.dispose();
    _importCtrl.dispose();
    super.dispose();
  }

  int get _pickedCount => [
        for (final c in _candidates)
          if (c.selected && c.status == CandidateStatus.ok) c,
      ].length;

  int get _okCount => [
        for (final c in _candidates)
          if (c.status == CandidateStatus.ok) c,
      ].length;

  int get _knownCount => [
        for (final c in _candidates)
          if (c.status == CandidateStatus.known) c,
      ].length;

  bool get _busy => _running || _importing;

  // ==================== 动作 ====================

  Future<void> _start() async {
    if (_busy) return;
    final kw = _kwCtrl.text.trim();
    if (kw.isEmpty) {
      _toast('请输入查找关键词');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _running = true;
      _candidates = [];
      _notes.clear();
    });
    final items = await SiteDiscoveryService.discover(
      DiscoveryRequest(
        keyword: kw,
        useEngine: _useEngine,
        useGithub: _useGithub,
        useFriend: _useFriend,
      ),
      onUpdate: _onUpdate,
      onNote: _onNote,
      isCancelled: () => !mounted || !_running,
    );
    if (!mounted) return;
    setState(() {
      _candidates = items;
      _running = false;
    });
  }

  void _stop() {
    if (!_running) return;
    setState(() => _running = false);
  }

  void _onUpdate(List<SiteCandidate> snapshot) {
    if (!mounted) return;
    setState(() => _candidates = snapshot);
  }

  void _onNote(String msg) {
    if (!mounted) return;
    setState(() {
      if (_notes.length >= 40) _notes.removeAt(0);
      _notes.add(msg);
    });
  }

  /// 从订阅地址导入：弹窗填地址 → 拉取解析 → 并入列表 → 统一探测确认
  Future<void> _importFromUrl() async {
    if (_busy) return;
    final parsed = await showDialog<List<SiteCandidate>>(
      context: context,
      builder: (dialogContext) {
        var loading = false;
        var error = '';
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('从订阅地址导入', style: TextStyle(fontSize: 17)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _importCtrl,
                      maxLines: 2,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: '订阅地址',
                        hintText: 'https://example.com/sites.json',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '粘贴站点清单 JSON（{"sites":[{"name","base"}]} 或顶层数组），'
                      '解析出的候选同样先探测再确认',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey,
                          height: 1.4),
                    ),
                    if (loading) ...[
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('正在拉取并解析…', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        '解析失败：$error',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              actions: [
                TextButton(
                  onPressed:
                      loading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final raw = _importCtrl.text.trim();
                          final base = PlayLineResolver.normalizeBase(raw);
                          if (raw.isEmpty || Uri.tryParse(base) == null) {
                            setDialogState(() => error = '请填写有效的订阅地址');
                            return;
                          }
                          setDialogState(() {
                            loading = true;
                            error = '';
                          });
                          final text =
                              await SiteDiscoveryService.fetchText(raw);
                          if (text == null || text.isEmpty) {
                            setDialogState(() {
                              loading = false;
                              error = '地址无响应或返回为空';
                            });
                            return;
                          }
                          try {
                            final items =
                                SiteDiscoveryService.parseSubscription(text);
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, items);
                            }
                          } on FormatException catch (e) {
                            setDialogState(() {
                              loading = false;
                              error = e.message;
                            });
                          }
                        },
                  child: const Text('解析'),
                ),
              ],
            );
          },
        );
      },
    );
    if (parsed == null || !mounted) return;

    setState(() {
      _importing = true;
      _candidates = SiteDiscoveryService.mergeCandidates(_candidates, parsed);
      _notes.add('从订阅地址解析出 ${parsed.length} 个候选，开始探测');
    });
    await SiteDiscoveryService.probeCandidates(
      _candidates,
      onUpdate: _onUpdate,
      isCancelled: () => !mounted || !_importing,
    );
    if (!mounted) return;
    setState(() => _importing = false);
  }

  Future<void> _addAll() async {
    final picked = [
      for (final c in _candidates)
        if (c.selected && c.status == CandidateStatus.ok) c,
    ];
    if (picked.isEmpty) return;
    for (final c in picked) {
      await PlayLineResolver.addCustom(
        name: c.displayName,
        base: c.base,
        mode: c.mode ?? PlayLineMode.api,
      );
    }
    debugPrint('[DISC] added ${picked.length} sites');
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(true); // 由入口页提示；本页直接作为首页时自行提示
    } else {
      _toast('已加入 ${picked.length} 个站点');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        width: 240,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  // ==================== 视图 ====================

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('在线发现资源站'),
        actions: [
          IconButton(
            tooltip: '从订阅地址导入',
            icon: const Icon(Icons.link_rounded),
            onPressed: _busy ? null : _importFromUrl,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _controls(outline),
          if (_notes.isNotEmpty) _noteBar(outline),
          Expanded(child: _body(outline)),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  /// 关键词 + 来源开关 + 开始/停止
  Widget _controls(Color outline) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _kwCtrl,
            enabled: !_busy,
            maxLength: 24,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              counterText: '',
              labelText: '查找关键词',
              hintText: '默认「短剧」，拼进查询串用于搜索资源站 / API',
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded, size: 18),
            ),
            onSubmitted: (_) => _start(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _sourceChip('搜索引擎', _useEngine,
                  (v) => setState(() => _useEngine = v), outline),
              _sourceChip('GitHub', _useGithub,
                  (v) => setState(() => _useGithub = v), outline),
              _sourceChip('友链扩展', _useFriend,
                  (v) => setState(() => _useFriend = v), outline),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _start,
                  icon: _running
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore_rounded, size: 18),
                  label: Text(_running ? '查找中…' : '开始查找'),
                ),
              ),
              if (_running) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _stop,
                  child: const Text('停止'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '查找关键词会发送给所选来源；站点地址仅在本机探测，不上传任何本地数据',
            style: TextStyle(
                fontSize: 11,
                color: outline.withValues(alpha: 0.85),
                height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _sourceChip(
      String label, bool value, ValueChanged<bool> onChanged, Color outline) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      selected: value,
      visualDensity: VisualDensity.compact,
      onSelected: _busy ? null : onChanged,
      side: BorderSide(color: outline.withValues(alpha: 0.35)),
    );
  }

  Widget _noteBar(Color outline) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: outline.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _notes.last,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, color: outline, height: 1.4),
      ),
    );
  }

  Widget _body(Color outline) {
    if (_candidates.isEmpty) {
      if (_busy) {
        return LoadingView(
            text: _importing ? '正在探测导入的候选…' : '正在从公网查找候选站点…');
      }
      return const EmptyView(
          message: '输入关键词开始查找，或点右上角从订阅地址导入');
    }
    return ListView.separated(
      padding: EdgeInsets.only(top: 4, bottom: AppLayout.scrollBottom(context)),
      itemCount: _candidates.length,
      separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
      itemBuilder: (context, index) => _candidateTile(_candidates[index]),
    );
  }

  /// 进度/汇总状态行
  Widget _statusLine(Color outline) {
    if (_busy) {
      return Text(
        '已发现 ${_candidates.length} 个候选 · 可用 $_okCount 个',
        style: TextStyle(fontSize: 11.5, color: outline),
      );
    }
    if (_candidates.isEmpty) return const SizedBox.shrink();
    return Text(
      '候选 ${_candidates.length} 个 · 可用 $_okCount 个'
      '${_knownCount > 0 ? ' · 已存在 $_knownCount 个' : ''}',
      style: TextStyle(fontSize: 11.5, color: outline),
    );
  }

  Widget _candidateTile(SiteCandidate c) {
    final outline = Theme.of(context).colorScheme.outline;
    final seed = Theme.of(context).colorScheme.primary;
    final known = c.status == CandidateStatus.known;
    final ok = c.status == CandidateStatus.ok;
    final dim = !ok && !known && c.status != CandidateStatus.probing;

    return CheckboxListTile(
      value: c.selected,
      dense: false,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      enabled: ok && !_busy,
      onChanged: (v) => setState(() => c.selected = v ?? false),
      title: Row(
        children: [
          Flexible(
            child: Text(
              c.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: dim ? outline : null,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _badge(c.source.label, outline, filled: false),
          if (ok && c.mode != null)
            _badge(
              c.mode == PlayLineMode.api ? '标准接口' : '网页解析',
              seed,
              filled: true,
            ),
          if (known) _badge('已存在', outline, filled: false),
          if (c.status == CandidateStatus.probing)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          _subtitle(c),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: outline, height: 1.4),
        ),
      ),
    );
  }

  String _subtitle(SiteCandidate c) => switch (c.status) {
        CandidateStatus.ok => _okSubtitle(c),
        CandidateStatus.failed => '${c.base} · ${c.failReason ?? '不可用'}',
        CandidateStatus.known => '${c.base} · 已在站点库中，无需重复添加',
        CandidateStatus.probing => '${c.base} · 正在探测…',
        CandidateStatus.pending => '${c.base} · 排队中',
      };

  String _okSubtitle(SiteCandidate c) {
    final ms = c.latencyMs == null ? '' : ' · ${c.latencyMs}ms';
    final sample = (c.sampleTitle?.isNotEmpty ?? false)
        ? ' · 样例：${c.sampleTitle}'
        : '';
    return '${c.base}$ms$sample';
  }

  Widget _badge(String text, Color color, {required bool filled}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.14) : Colors.transparent,
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final count = _pickedCount;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 6, 16, AppLayout.scrollBottom(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_candidates.isNotEmpty) ...[
              _statusLine(Theme.of(context).colorScheme.outline),
              const SizedBox(height: 6),
            ],
            FilledButton.icon(
              onPressed: count == 0 || _busy ? null : _addAll,
              icon: const Icon(Icons.add_task_rounded, size: 18),
              label: Text(count == 0 ? '勾选可用站点后加入' : '加入所选（$count）'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
