import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/device_service.dart';
import '../../core/services/token_service.dart';
import '../../core/state/settings_provider.dart';
import '../../core/state/theme_provider.dart';
import '../../core/theme/app_theme.dart';

/// 设置页面（所有用户可修改配置项统一收纳于此，全局默认值以本页为准）
///
/// 1. 主题设置区域：明暗模式切换 + 自定义APP主题主色选择
/// 2. 播放器全局默认配置区域：默认播放倍速 0.75x ~ 5x
/// 3. 缓存管理区域：查看/一键清除图片缓存
/// 4. 账号与设备区域：重置设备 ID / 退出登录（清除token）
/// 5. 关于页面区域：项目版本信息
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
    _loadCacheSize();
    _loadVersion();
  }

  Future<void> _loadCacheSize() async {
    final bytes = await CacheService.imageSizeBytes();
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
    if (!mounted) return;
    setState(() => _cacheSize = '0 B');
    _toast('图片缓存已清除');
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
            child: ListTile(
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
          ),

          // ==================== 3. 缓存管理区域 ====================
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

          // ==================== 4. 账号与设备区域 ====================
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

          // ==================== 5. 关于页面区域 ====================
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
}
