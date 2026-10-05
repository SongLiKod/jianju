import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/services/device_service.dart';
import 'core/services/favorite_service.dart';
import 'core/services/history_service.dart';
import 'core/services/search_history_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/tray_service.dart';
import 'core/services/window_service.dart';
import 'core/state/settings_provider.dart';
import 'core/state/theme_provider.dart';

/// 简剧 - 纯净短剧客户端（学习研究项目）
///
/// 对接红果短剧私有 API，客户端本地过滤全部广告，
/// 双端（Android + Windows）统一 UI。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 播放器引擎初始化（libmpv，Android + Windows 双端）
  MediaKit.ensureInitialized();

  // 本地存储 / 设备信息 / 本地数据初始化
  await StorageService.init();

  // Windows 桌面窗口（标题 / 最小尺寸 / 恢复上次窗口位置，全屏播放依赖）
  await WindowService.init();

  // 系统托盘（简剧图标 + 右键菜单，关闭窗口时收进托盘）
  await TrayService.init();

  await DeviceService.init();
  FavoriteService.init();
  HistoryService.init();
  SearchHistoryService.init();

  final themeProvider = ThemeProvider()..load();
  final settingsProvider = SettingsProvider()..load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
      ],
      child: const JianjuApp(),
    ),
  );
}
