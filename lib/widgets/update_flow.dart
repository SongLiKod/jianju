import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/services/update_service.dart';

/// 应用内更新弹窗：确认 → 静默下载（进度可取消）→ 应用内安装
///
/// 全程不离开软件：下载在后台静默完成，安装走系统 PackageInstaller，
/// 确认框浮在本应用之上；仅首次需要跳系统设置开「允许来自此来源」，
/// 授权返回后自动续上安装（监听 resumed 生命周期）。
class UpdateFlow extends StatefulWidget {
  const UpdateFlow({super.key, required this.info, this.autoStart = false});

  final UpdateInfo info;

  /// 启动自动检查进入：只弹确认框，不自动下载（由用户点「立即更新」）
  final bool autoStart;

  static Future<void> show(
    BuildContext context,
    UpdateInfo info, {
    bool autoStart = false,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateFlow(info: info, autoStart: autoStart),
    );
  }

  @override
  State<UpdateFlow> createState() => _UpdateFlowState();
}

enum _Phase { confirm, downloading, blocked, installing, error }

class _UpdateFlowState extends State<UpdateFlow> with WidgetsBindingObserver {
  _Phase _phase = _Phase.confirm;
  int _received = 0;
  int _total = 0;
  String _error = '';
  String _current = '';
  File? _file;
  CancelToken? _token;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UpdateService.listenInstallStatus(_onInstallStatus);
    _loadCurrent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UpdateService.cancelInstallStatusListener();
    _token?.cancel();
    super.dispose();
  }

  /// 系统安装回执：成功即收起弹窗（系统随后重启本应用）；失败展示可读原因
  void _onInstallStatus(int status, String message) {
    if (!mounted) return;
    if (status == 0) {
      debugPrint('[UPD] 安装成功');
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _phase = _Phase.error;
      _error = UpdateService.humanizeInstallError(message);
    });
  }

  /// 从系统「允许来自此来源」页回来：已授权就自动续上安装
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_phase != _Phase.blocked) return;
    _resumeAfterSettings();
  }

  Future<void> _loadCurrent() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _current = info.version);
    } catch (_) {}
  }

  Future<void> _startDownload() async {
    if (widget.info.apkUrl == null) {
      setState(() {
        _phase = _Phase.error;
        _error = '该版本没有安卓安装包（APK）';
      });
      return;
    }
    setState(() {
      _phase = _Phase.downloading;
      _received = 0;
      _total = widget.info.apkSize;
      _error = '';
    });
    _token = CancelToken();
    final file = await UpdateService.downloadApk(widget.info, (r, t) {
      if (!mounted) return;
      setState(() {
        _received = r;
        if (t > 0) _total = t;
      });
    }, cancelToken: _token!);
    if (!mounted) return;
    if (_token?.isCancelled ?? false) {
      setState(() => _phase = _Phase.confirm);
      return;
    }
    if (file == null) {
      setState(() {
        _phase = _Phase.error;
        _error = '下载失败，请检查网络后重试';
      });
      return;
    }
    _file = file;
    if (await UpdateService.canInstall()) {
      if (mounted) await _install();
    } else if (mounted) {
      setState(() => _phase = _Phase.blocked);
    }
  }

  Future<void> _install() async {
    final file = _file;
    if (file == null || !mounted) return;
    setState(() => _phase = _Phase.installing);
    final code = await UpdateService.installApk(file.path);
    if (!mounted || code == null) return; // 已提交，等系统回执（_onInstallStatus）
    if (code == 'blocked') {
      setState(() => _phase = _Phase.blocked);
    } else {
      setState(() {
        _phase = _Phase.error;
        _error = UpdateService.humanizeInstallError(code);
      });
    }
  }

  Future<void> _resumeAfterSettings() async {
    if (await UpdateService.canInstall() && mounted) await _install();
  }

  Future<void> _openReleasePage() async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [widget.info.releasePage]);
      } else {
        debugPrint('[UPD] 打开发布页 ${widget.info.releasePage}');
      }
    } catch (e) {
      debugPrint('[UPD] 打开发布页失败：$e');
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _phase != _Phase.downloading,
      child: AlertDialog(
        title: Text(_title()),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _body(scheme),
        ),
        actions: _actions(scheme),
      ),
    );
  }

  String _title() {
    switch (_phase) {
      case _Phase.confirm:
        return '发现新版本 ${widget.info.version}';
      case _Phase.downloading:
        return '下载更新中';
      case _Phase.blocked:
        return '需要安装授权';
      case _Phase.installing:
        return '正在安装更新';
      case _Phase.error:
        return '更新失败';
    }
  }

  Widget _body(ColorScheme scheme) {
    switch (_phase) {
      case _Phase.confirm:
        final notes = widget.info.notes.trim();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _current.isEmpty
                  ? '当前版本 ${widget.info.version}'
                  : '当前版本 $_current → 新版本 ${widget.info.version}',
              style: const TextStyle(fontSize: 14),
            ),
            if (widget.info.apkSize > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '安装包 ${_mb(widget.info.apkSize)} · 下载后在应用内直接安装',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ),
            if (notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      notes,
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                ),
              ),
          ],
        );
      case _Phase.downloading:
        final total = _total;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: total > 0 ? (_received / total).clamp(0.0, 1.0) : null,
            ),
            const SizedBox(height: 12),
            Text(
              '${_mb(_received)} / ${total > 0 ? _mb(total) : '?'}'
              '（静默下载，可随时取消）',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ],
        );
      case _Phase.blocked:
        return const Text(
          '系统尚未允许本应用安装应用。点下方「去开启」打开系统开关'
          '（仅此一次），开启后返回本弹窗会自动继续安装，全程不离开软件。',
          style: TextStyle(fontSize: 13, height: 1.6),
        );
      case _Phase.installing:
        return const Text(
          '已唤起系统安装确认框，请点击其中的「安装」。'
          '确认后应用将原地更新，不会退出到桌面。',
          style: TextStyle(fontSize: 13, height: 1.6),
        );
      case _Phase.error:
        return Text(_error, style: const TextStyle(fontSize: 13, height: 1.6));
    }
  }

  List<Widget> _actions(ColorScheme scheme) {
    switch (_phase) {
      case _Phase.confirm:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: Platform.isAndroid
                ? _startDownload
                : _openReleasePage,
            child: Text(Platform.isAndroid ? '立即更新' : '打开发布页'),
          ),
        ];
      case _Phase.downloading:
        return [
          TextButton(
            onPressed: () => _token?.cancel(),
            child: const Text('取消'),
          ),
        ];
      case _Phase.blocked:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => UpdateService.openInstallSettings(),
            child: const Text('去开启'),
          ),
        ];
      case _Phase.installing:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ];
      case _Phase.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: _startDownload,
            child: const Text('重试'),
          ),
        ];
    }
  }

  static String _mb(int bytes) =>
      '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
}
