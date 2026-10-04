import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/device_service.dart';
import '../../core/services/play_lines.dart';
import '../../core/services/prebuffer_service.dart';
import '../../core/services/token_service.dart';
import '../../core/state/settings_provider.dart';
import '../../core/state/theme_provider.dart';
import '../../core/theme/app_theme.dart';

/// 设置页面（所有用户可修改配置项统一收纳于此，全局默认值以本页为准）
///
/// 1. 主题设置区域：明暗模式切换 + 自定义APP主题主色选择
/// 2. 播放器全局默认配置区域：默认播放倍速 0.75x ~ 5x
/// 3. 数据源区域：官方网页源 / 52api 红果源切换 + apikey 配置 + 整站站点列表
/// 4. 缓存管理区域：查看/一键清除图片缓存
/// 5. 账号与设备区域：重置设备 ID / 退出登录（清除token）
/// 6. 关于页面区域：项目版本信息
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _cacheSize = '计算中...';
  String _version = '';

  @override
  void initState() {
    super.initState();
    debugPrint('[NAV] settings.init');
    _loadCacheSize();
    _loadVersion();
  }

  Future<void> _loadCacheSize() async {
    final bytes = await CacheService.imageSizeBytes() +
        await PrebufferService.totalBytes();
    if (!mounted) return;
    setState(() => _cacheSize = CacheService.formatSize(bytes));
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = info.version);
  }

  Future<void> _clearCache() async {
    await CacheService.clearImageCache();
    await PrebufferService.clear();
    if (!mounted) return;
    setState(() => _cacheSize = '0 B');
    _toast('缓存已清除（图片 + 跨集预缓存）');
  }

  Future<void> _resetDeviceId() async {
    final confirmed = await _confirm('重置设备 ID',
        '将重新生成一套随机设备信息，用于降低风控概率。确定重置吗？');
    if (confirmed != true) return;
    await DeviceService.reset();
    if (!mounted) return;
    _toast('设备 ID 已重置');
  }

  Future<void> _logout() async {
    if (!TokenService.hasToken) {
      _toast('当前无登录 Token');
      return;
    }
    final confirmed = await _confirm('退出登录', '将清除本地保存的登录 Token。确定退出吗？');
    if (confirmed != true) return;
    await TokenService.logout();
    if (!mounted) return;
    _toast('已退出登录');
  }

  Future<bool?> _confirm(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 17)),
        content: Text(content, style: const TextStyle(fontSize: 14)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定')),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        width: 220,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final settings = context.watch<SettingsProvider>();
    final seed = AppPalette.colors[theme.colorIndex].color;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final outline = Theme.of(context).colorScheme.outline;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: EdgeInsets.only(
          top: 8,
          bottom: MediaQuery.paddingOf(context).bottom + 96,
        ),
        children: [
          // ==================== 1. 主题设置区域 ====================
          _sectionTitle('主题'),
          _groupContainer(
            isDark,
            children: [
              // 明暗模式切换（浅色 / 深色 / 跟随系统）
              Column(
                children: [
                  _radioTile(context, Icons.light_mode_outlined, '浅色模式',
                      ThemeMode.light, theme.mode),
                  _radioTile(context, Icons.dark_mode_outlined, '深色模式',
                      ThemeMode.dark, theme.mode),
                  _radioTile(context, Icons.brightness_auto_outlined,
                      '跟随系统', ThemeMode.system, theme.mode),
                ],
              ),
              const Divider(indent: 16),
              // 自定义主题主色选择
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.palette_outlined,
                            size: 18, color: outline),
                        const SizedBox(width: 8),
                        Text('主题主色',
                            style: TextStyle(fontSize: 14, color: outline)),
                        const Spacer(),
                        Text(AppPalette.colors[theme.colorIndex].name,
                            style: TextStyle(
                                fontSize: 13,
                                color: seed,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (var i = 0; i < AppPalette.colors.length; i++)
                          _colorDot(
                            AppPalette.colors[i].color,
                            selected: i == theme.colorIndex,
                            onTap: () =>
                                context.read<ThemeProvider>().setColorIndex(i),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ==================== 2. 播放器全局默认配置区域 ====================
          _sectionTitle('播放器'),
          _groupContainer(
            isDark,
            children: [
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading: Icon(Icons.speed_rounded, color: outline, size: 22),
                title: const Text('默认播放倍速',
                    style: TextStyle(fontSize: 15)),
                subtitle: Text('打开视频自动加载，范围 0.75x ~ 5x',
                    style: TextStyle(fontSize: 12, color: outline)),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: seed.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _speedText(settings.defaultSpeed),
                    style: TextStyle(
                        color: seed,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ),
                onTap: () async {
                  final provider = context.read<SettingsProvider>();
                  final picked = await _pickDefaultSpeed(settings.defaultSpeed, seed);
                  if (picked != null) {
                    provider.setDefaultSpeed(picked);
                  }
                },
              ),
              const Divider(indent: 16),
              // 预载下一集：本集结尾前提前解析下一集，换集秒开不黑屏
              SwitchListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                secondary: Icon(Icons.flash_auto_rounded,
                    color: outline, size: 22),
                title: const Text('预载下一集',
                    style: TextStyle(fontSize: 15)),
                subtitle: Text(
                  '本集结束前 ${settings.preloadLeadSec} 秒提前解析下一集直链'
                  '（配合缓冲大小的跨集缓存，换集无缝接上）',
                  style: TextStyle(fontSize: 12, color: outline),
                ),
                value: settings.preloadNext,
                onChanged: (v) => context.read<SettingsProvider>().setPreloadNext(v),
              ),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading: Icon(Icons.timer_outlined, color: outline, size: 22),
                title: const Text('提前预载时间',
                    style: TextStyle(fontSize: 15)),
                subtitle: Text('距本集结尾还有多久开始预载',
                    style: TextStyle(fontSize: 12, color: outline)),
                trailing: _chip('${settings.preloadLeadSec} 秒', seed, settings.preloadNext),
                enabled: settings.preloadNext,
                onTap: () async {
                  final provider = context.read<SettingsProvider>();
                  final v = await _pickInt(
                    '提前预载时间',
                    AppConstants.preloadLeadOptions,
                    settings.preloadLeadSec,
                    (n) => '$n 秒',
                    seed,
                  );
                  if (v != null) provider.setPreloadLeadSec(v);
                },
              ),
              const Divider(indent: 16),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading: Icon(Icons.network_check_rounded,
                    color: outline, size: 22),
                title: const Text('缓冲大小（网络提速）',
                    style: TextStyle(fontSize: 15)),
                subtitle: Text(
                    '总预算跨集使用：当前集读取余量 + 自动预缓存下一集、'
                    '下下集……换集秒开不黑屏',
                    style: TextStyle(fontSize: 12, color: outline)),
                trailing: _chip(_bufferText(settings.bufferSecs), seed, true),
                onTap: () async {
                  final provider = context.read<SettingsProvider>();
                  final v = await _pickInt(
                    '缓冲大小',
                    AppConstants.bufferOptions,
                    settings.bufferSecs,
                    _bufferText,
                    seed,
                    onCustom: () => _pickCustomBufferSecs(settings.bufferSecs),
                  );
                  if (v != null) provider.setBufferSecs(v);
                },
              ),
              const Divider(indent: 16),
              SwitchListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                secondary:
                    Icon(Icons.timeline_rounded, color: outline, size: 22),
                title: const Text('底部进度条',
                    style: TextStyle(fontSize: 15)),
                subtitle: Text('播放时在底部显示一条细进度线（控件隐藏也可见）',
                    style: TextStyle(fontSize: 12, color: outline)),
                value: settings.slimProgress,
                onChanged: (v) => context.read<SettingsProvider>().setSlimProgress(v),
              ),
            ],
          ),

          // ==================== 3. 数据源区域 ====================
          _sectionTitle('数据源'),
          _groupContainer(
            isDark,
            children: [
              _sourceTile(
                context,
                icon: Icons.language_rounded,
                label: '官方网页源',
                desc: '红果官网 · 免配置 · 前 3 集可播',
                selected:
                    settings.dataSource == AppConstants.dataSourceWeb,
                seed: seed,
                onTap: () => context
                    .read<SettingsProvider>()
                    .setDataSource(AppConstants.dataSourceWeb),
              ),
              const Divider(indent: 16),
              _sourceTile(
                context,
                icon: Icons.cloud_outlined,
                label: '52api 红果源',
                desc: '全集可播 · 需 apikey',
                selected:
                    settings.dataSource == AppConstants.dataSourceApi52,
                seed: seed,
                onTap: () async {
                  final provider = context.read<SettingsProvider>();
                  if (!provider.hasApi52Key) {
                    final saved = await _editApiKey();
                    if (saved != true) return;
                  }
                  await provider.setDataSource(AppConstants.dataSourceApi52);
                },
              ),
              const Divider(indent: 16),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading: Icon(Icons.vpn_key_outlined,
                    color: outline, size: 22),
                title: const Text('52api apikey',
                    style: TextStyle(fontSize: 15)),
                subtitle: Text(
                  settings.hasApi52Key
                      ? '已配置 ${_maskKey(settings.apiKey52)}'
                      : '未配置（52api.cn 注册开通红果接口）',
                  style: TextStyle(fontSize: 12, color: outline),
                ),
                trailing: Icon(Icons.edit_outlined,
                    color: outline.withValues(alpha: 0.6), size: 20),
                onTap: _editApiKey,
              ),
            ],
          ),

          // ==================== 3.5 整站站点（maccms API 站 + 自定义） ====================
          _sectionTitle('整站站点'),
          _groupContainer(
            isDark,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Text(
                  '选中后首页、分类、榜单、搜索、详情与播放数据全部来自该站点'
                  '（标准 maccms 接口站可自定义添加）',
                  style: TextStyle(fontSize: 12, color: outline, height: 1.4),
                ),
              ),
              const Divider(indent: 16),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading:
                    Icon(Icons.add_circle_outline_rounded, color: seed, size: 22),
                title: Text('添加自定义站点',
                    style: TextStyle(
                        fontSize: 15,
                        color: seed,
                        fontWeight: FontWeight.w600)),
                subtitle: Text('标准 maccms 接口站 / 网页解析站，自动检测可用性',
                    style: TextStyle(fontSize: 12, color: outline)),
                onTap: _addCustomSite,
              ),
              for (final line in PlayLineResolver.allLines)
                if (!line.isCustom && line.mode == PlayLineMode.api) ...[
                  const Divider(indent: 16),
                  _sourceTile(
                    context,
                    icon: Icons.dns_outlined,
                    label: line.name,
                    desc: '整站数据源 · 首页/搜索/详情/播放全走该站',
                    selected: settings.dataSource ==
                        AppConstants.dataSourceOfLine(line.id),
                    seed: seed,
                    onTap: () => context
                        .read<SettingsProvider>()
                        .setDataSource(AppConstants.dataSourceOfLine(line.id)),
                  ),
                ],
              for (final line in PlayLineResolver.customLines) ...[
                const Divider(indent: 16),
                _customLineTile(context, line, settings, seed, outline),
              ],
            ],
          ),

          // ==================== 4. 缓存管理区域 ====================
          _sectionTitle('缓存管理'),
          _groupContainer(
            isDark,
            children: [
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading:
                    Icon(Icons.image_outlined, color: outline, size: 22),
                title: const Text('图片缓存',
                    style: TextStyle(fontSize: 15)),
                trailing: Text(_cacheSize,
                    style: TextStyle(
                        fontSize: 13,
                        color: outline,
                        fontWeight: FontWeight.w600)),
              ),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading:
                    Icon(Icons.cleaning_services_outlined, color: outline, size: 22),
                title: const Text('一键清除图片缓存',
                    style: TextStyle(fontSize: 15)),
                trailing: Icon(Icons.chevron_right_rounded,
                    color: outline.withValues(alpha: 0.6)),
                onTap: _clearCache,
              ),
            ],
          ),

          // ==================== 5. 账号与设备区域 ====================
          _sectionTitle('账号与设备'),
          _groupContainer(
            isDark,
            children: [
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading:
                    Icon(Icons.restart_alt_rounded, color: outline, size: 22),
                title: const Text('重置设备 ID',
                    style: TextStyle(fontSize: 15)),
                subtitle: Text('重新生成随机设备信息，降低风控概率',
                    style: TextStyle(fontSize: 12, color: outline)),
                trailing: Icon(Icons.chevron_right_rounded,
                    color: outline.withValues(alpha: 0.6)),
                onTap: _resetDeviceId,
              ),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading:
                    Icon(Icons.logout_rounded, color: outline, size: 22),
                title: const Text('退出登录',
                    style: TextStyle(fontSize: 15)),
                subtitle: Text('清除本地保存的登录 Token',
                    style: TextStyle(fontSize: 12, color: outline)),
                trailing: Icon(Icons.chevron_right_rounded,
                    color: outline.withValues(alpha: 0.6)),
                onTap: _logout,
              ),
            ],
          ),

          // ==================== 6. 关于页面区域 ====================
          _sectionTitle('关于'),
          _groupContainer(
            isDark,
            children: [
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading:
                    Icon(Icons.play_circle_outline_rounded, color: outline, size: 22),
                title: const Text(AppConstants.appName,
                    style: TextStyle(fontSize: 15)),
                subtitle: Text(AppConstants.appTagline,
                    style: TextStyle(fontSize: 12, color: outline)),
              ),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading:
                    Icon(Icons.info_outline_rounded, color: outline, size: 22),
                title: const Text('版本信息', style: TextStyle(fontSize: 15)),
                trailing: Text(_version.isEmpty ? '...' : _version,
                    style: TextStyle(
                        fontSize: 13,
                        color: outline,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '仅用于个人学习研究 · 非商用',
              style: TextStyle(fontSize: 11, color: outline.withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 组件 ====================

  Widget _sectionTitle(String text) {
    final outline = Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: outline)),
    );
  }

  Widget _groupContainer(bool isDark,
      {List<Widget> children = const [], Widget? child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child ?? Column(children: children),
    );
  }

  Widget _radioTile(
      BuildContext context, IconData icon, String label, ThemeMode value, ThemeMode groupValue) {
    final outline = Theme.of(context).colorScheme.outline;
    final selected = groupValue == value;
    final seed = AppPalette.colors[context.watch<ThemeProvider>().colorIndex].color;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, size: 20, color: selected ? seed : outline),
      title: Text(label,
          style: TextStyle(
              fontSize: 14.5,
              color: selected ? seed : null,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? seed : outline.withValues(alpha: 0.5),
            width: selected ? 6 : 1.5,
          ),
        ),
      ),
      onTap: () => context.read<ThemeProvider>().setMode(value),
    );
  }

  Widget _colorDot(Color color, {required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: selected ? 38 : 32,
        height: selected ? 38 : 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : const Color(0xFF1C1C1E))
                : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8)]
              : null,
        ),
        child: selected
            ? const Icon(Icons.check_rounded,
                color: Colors.white, size: 18)
            : null,
      ),
    );
  }

  Future<double?> _pickDefaultSpeed(double current, Color seed) {
    return showModalBottomSheet<double>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('默认播放倍速',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: seed)),
                ),
              ),
              ...AppConstants.playbackSpeeds.map((s) {
                final selected = s == current;
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: selected
                      ? Icon(Icons.check_rounded, color: seed, size: 20)
                      : const SizedBox(width: 20),
                  title: Text(_speedText(s)),
                  selected: selected,
                  selectedColor: seed,
                  onTap: () => Navigator.pop(sheetContext, s),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  static String _speedText(double s) {
    if (s == s.roundToDouble()) return '${s.toInt()}.0x';
    return '${s}x';
  }

  static String _bufferText(int secs) =>
      secs < 60 ? '$secs秒' : '${secs ~/ 60}分钟';

  /// 数值选项胶囊（trailing 用）
  Widget _chip(String text, Color seed, bool enabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: seed.withValues(alpha: enabled ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: enabled ? seed : Colors.grey,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  /// 通用整数选项选择器
  Future<int?> _pickInt(String title, List<int> options, int current,
      String Function(int) label, Color seed,
      {Future<int?> Function()? onCustom}) {
    return showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: seed)),
                ),
              ),
              ...options.map((v) {
                final selected = v == current;
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: selected
                      ? Icon(Icons.check_rounded, color: seed, size: 20)
                      : const SizedBox(width: 20),
                  title: Text(label(v)),
                  selected: selected,
                  selectedColor: seed,
                  onTap: () => Navigator.pop(sheetContext, v),
                );
              }),
              if (onCustom != null)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.edit_rounded, size: 20),
                  title: const Text('自定义…'),
                  onTap: () async {
                    final v = await onCustom();
                    if (v != null && sheetContext.mounted) {
                      Navigator.pop(sheetContext, v);
                    }
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 自定义缓冲大小（分钟输入，1~60），返回秒数
  Future<int?> _pickCustomBufferSecs(int currentSecs) {
    final controller = TextEditingController(
        text: currentSecs >= 60 && currentSecs % 60 == 0
            ? '${currentSecs ~/ 60}'
            : '');
    return showDialog<int>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('自定义缓冲大小'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '分钟数',
                hintText: '1 - 60',
                suffixText: '分钟',
                errorText: error,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  final mins = int.tryParse(controller.text.trim()) ?? 0;
                  if (mins < 1 || mins > 60) {
                    setDialogState(() => error = '请输入 1~60 之间的分钟数');
                    return;
                  }
                  Navigator.pop(ctx, mins * 60);
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== 数据源 ====================

  Widget _sourceTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String desc,
    required bool selected,
    required Color seed,
    required VoidCallback onTap,
  }) {
    final outline = Theme.of(context).colorScheme.outline;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, size: 22, color: selected ? seed : outline),
      title: Text(label,
          style: TextStyle(
              fontSize: 15,
              color: selected ? seed : null,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
      subtitle: Text(desc, style: TextStyle(fontSize: 12, color: outline)),
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? seed : outline.withValues(alpha: 0.5),
            width: selected ? 6 : 1.5,
          ),
        ),
      ),
      onTap: onTap,
    );
  }

  // ==================== 自定义站点 ====================

  Widget _customLineTile(BuildContext context, PlayLine line,
      SettingsProvider settings, Color seed, Color outline) {
    final selected = line.mode == PlayLineMode.api &&
        settings.dataSource == AppConstants.dataSourceOfLine(line.id);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading:
          Icon(Icons.dns_outlined, size: 22, color: selected ? seed : outline),
      title: Text(
        line.name,
        style: TextStyle(
          fontSize: 15,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? seed : null,
        ),
      ),
      subtitle: Text(
        '${line.mode == PlayLineMode.api ? '自定义整站源' : '自定义网页解析'} · ${line.base}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: outline),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (line.mode == PlayLineMode.api)
            selected
                ? Icon(Icons.check_circle_rounded, color: seed, size: 20)
                : Icon(Icons.circle_outlined,
                    size: 18, color: outline.withValues(alpha: 0.4)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline_rounded,
                size: 20, color: Colors.redAccent.withValues(alpha: 0.85)),
            tooltip: '删除站点',
            onPressed: () => _deleteCustom(line),
          ),
        ],
      ),
      onTap: line.mode == PlayLineMode.api
          ? () => context
              .read<SettingsProvider>()
              .setDataSource(AppConstants.dataSourceOfLine(line.id))
          : null,
    );
  }

  /// 添加自定义站点：填写地址 → 自动检测 → 通过即保存
  Future<void> _addCustomSite() async {
    final baseCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    var mode = PlayLineMode.api;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var testing = false;
        var error = '';
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('添加自定义站点', style: TextStyle(fontSize: 17)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: baseCtrl,
                      autofocus: true,
                      maxLines: 1,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: '站点地址',
                        hintText: 'example.com 或 https://example.com',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      maxLines: 1,
                      decoration: const InputDecoration(
                        labelText: '站点名称（可选）',
                        hintText: '留空自动取域名',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('标准接口'),
                          selected: mode == PlayLineMode.api,
                          onSelected: (_) => setDialogState(
                              () => mode = PlayLineMode.api),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('网页解析'),
                          selected: mode == PlayLineMode.html,
                          onSelected: (_) => setDialogState(
                              () => mode = PlayLineMode.html),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      mode == PlayLineMode.api
                          ? '接口模式可作整站源（首页/搜索/详情/播放全走该站）'
                          : '网页模式仅用于播放解析，不参与首页/搜索',
                      style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                    if (testing) ...[
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('正在检测站点可用性…',
                              style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        '检测未通过：$error',
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
                  onPressed: testing ? null : () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                if (error.isNotEmpty && !testing)
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(dialogContext, true),
                    child: const Text('仍要添加'),
                  ),
                FilledButton(
                  onPressed: testing
                      ? null
                      : () async {
                          final base =
                              PlayLineResolver.normalizeBase(baseCtrl.text);
                          if (base.isEmpty || Uri.tryParse(base) == null) {
                            setDialogState(() => error = '请填写有效的站点地址');
                            return;
                          }
                          setDialogState(() {
                            testing = true;
                            error = '';
                          });
                          final reason =
                              await PlayLineResolver.probeCustom(base, mode);
                          if (reason != null) {
                            setDialogState(() {
                              testing = false;
                              error = reason;
                            });
                            return;
                          }
                          final name = nameCtrl.text.trim().isEmpty
                              ? (Uri.tryParse(base)?.host ?? base)
                              : nameCtrl.text.trim();
                          await PlayLineResolver.addCustom(
                              name: name, base: base, mode: mode);
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        },
                  child: const Text('检测并添加'),
                ),
              ],
            );
          },
        );
      },
    );
    baseCtrl.dispose();
    nameCtrl.dispose();
    if (saved == true) {
      debugPrint('[SET] custom site added');
      if (!mounted) return;
      _toast('自定义站点已添加');
      setState(() {});
    }
  }

  Future<void> _deleteCustom(PlayLine line) async {
    final ok = await _confirm('删除站点', '确定删除自定义站点「${line.name}」吗？');
    if (ok != true) return;
    await PlayLineResolver.removeCustom(line.id);
    if (!mounted) return;
    // 数据源/锁定线路指向被删站点时同步复位（与 apikey 清除联动一致）
    final provider = context.read<SettingsProvider>();
    if (provider.dataSource == AppConstants.dataSourceOfLine(line.id)) {
      await provider.setDataSource(AppConstants.dataSourceWeb);
    }
    if (provider.pinnedLineId == line.id) {
      await provider.setPinnedLine('');
    }
    debugPrint('[SET] custom site removed ${line.id}');
    if (!mounted) return;
    setState(() {});
    _toast('站点已删除');
  }

  /// 编辑/清除 52api apikey，返回是否保存成功
  Future<bool> _editApiKey() async {
    final controller =
        TextEditingController(text: context.read<SettingsProvider>().apiKey52);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('52api apikey', style: TextStyle(fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 1,
          decoration: const InputDecoration(
            hintText: '粘贴 apikey（52api.cn 开通红果接口后获取）',
            helperText: '留空保存即清除',
            isDense: true,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存')),
        ],
      ),
    );
    final key = controller.text.trim();
    controller.dispose();
    if (saved != true) return false;
    if (!mounted) return true;
    await context.read<SettingsProvider>().setApiKey52(key);
    if (!mounted) return true;
    _toast(key.isEmpty ? 'apikey 已清除' : 'apikey 已保存');
    return true;
  }

  static String _maskKey(String key) {
    if (key.length <= 8) return '****';
    return '${key.substring(0, 4)}****${key.substring(key.length - 4)}';
  }
}
