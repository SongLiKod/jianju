import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/services/device_service.dart';
import 'core/services/favorite_service.dart';
import 'core/services/history_service.dart';
import 'core/services/storage_service.dart';
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

  // Windows 桌面窗口初始化（全屏播放需要）
  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
  }

  // 本地存储 / 设备信息 / 本地数据初始化
  await StorageService.init();
  await DeviceService.init();
  FavoriteService.init();
  HistoryService.init();

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
