import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../constants/app_constants.dart';

/// Windows 系统托盘（托盘图标 / 悬停提示 / 右键菜单）
///
/// - 图标来自 assets/icons/app_icon.ico，由 tray_manager 从 flutter_assets 目录读取
/// - 左键点击托盘：显示并聚焦主窗口
/// - 右键点击托盘：弹出「显示主界面 / 退出」菜单
/// - 窗口关闭按钮（配合 [WindowService] 的 preventClose）→ 隐藏到托盘，真正退出走菜单
class TrayService with TrayListener {
  TrayService._();

  static final TrayService instance = TrayService._();

  /// 托盘是否初始化成功：只有成功后窗口关闭按钮才改走「隐藏到托盘」
  bool enabled = false;

  static bool get _supported => !kIsWeb && Platform.isWindows;

  static Future<void> init() async {
    if (!_supported) return;
    try {
      await windowManager.ensureInitialized();
      trayManager.addListener(instance);
      // tray_manager 拼接规则：<exe 目录>\data\flutter_assets\<path>
      // 而 pubspec 声明的是 assets/icons/，打包后实际落在 flutter_assets\assets\icons\
      // 传错路径 LoadImage 返回 NULL 且不抛错 → 托盘图标透明/空白（静默失败）
      const iconPath = 'assets/icons/app_icon.ico';
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final iconFile = File('$exeDir/data/flutter_assets/$iconPath');
      if (!iconFile.existsSync()) {
        debugPrint('[TRAY] 托盘图标缺失: ${iconFile.path}');
      }
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip(AppConstants.appName);
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: '显示主界面'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出${AppConstants.appName}'),
      ]));
      // 托盘就绪后拦截原生关闭信号：点关闭按钮 → 收进托盘（见 WindowService.onWindowClose）
      await windowManager.setPreventClose(true);
      instance.enabled = true;
      debugPrint('[TRAY] ready');
    } catch (e) {
      instance.enabled = false;
      debugPrint('[TRAY] 托盘初始化失败: $e');
    }
  }

  /// 显示并聚焦主窗口（托盘左键 / 菜单「显示主界面」）
  Future<void> showMainWindow() async {
    if (!_supported) return;
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('[TRAY] 显示窗口失败: $e');
    }
  }

  /// 窗口隐藏到托盘（关闭按钮被拦截时调用）
  Future<bool> hideToTray() async {
    if (!enabled) return false;
    try {
      await windowManager.hide();
      return true;
    } catch (e) {
      debugPrint('[TRAY] 隐藏窗口失败: $e');
      return false;
    }
  }

  /// 真正退出：解除关闭拦截 → 摧毁托盘图标 → 关闭窗口
  Future<void> exitApp() async {
    try {
      await windowManager.setPreventClose(false);
      await trayManager.destroy();
      await windowManager.destroy();
    } catch (e) {
      debugPrint('[TRAY] 退出失败: $e');
    }
  }

  @override
  void onTrayIconMouseDown() => showMainWindow();

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      showMainWindow();
    } else if (menuItem.key == 'exit') {
      exitApp();
    }
  }
}
