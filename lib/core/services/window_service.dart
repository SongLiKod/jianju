import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../constants/app_constants.dart';
import 'storage_service.dart';
import 'tray_service.dart';

/// Windows 桌面窗口管理
///
/// 1. 启动：设置窗口标题、最小可缩放尺寸，无历史记录时居中显示
/// 2. 运行：拖动 / 缩放结束后把窗口位置与尺寸落盘（去抖，避免高频写入）
/// 3. 下次启动恢复上次的窗口位置与尺寸（尺寸过小或数据非法时忽略）
class WindowService with WindowListener {
  WindowService._();

  static final WindowService instance = WindowService._();

  /// 桌面端窗口最小尺寸（与断点联动，保证侧边栏布局不塌）
  static const Size minSize = Size(1024, 640);

  static const String _keyBounds = 'local.window_bounds';
  static const Duration _saveDelay = Duration(milliseconds: 700);

  Timer? _saveTimer;

  static Future<void> init() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await windowManager.ensureInitialized();
      final saved = instance._readBounds();
      await windowManager.waitUntilReadyToShow(
        WindowOptions(
          minimumSize: minSize,
          title: AppConstants.appName,
          center: saved == null,
        ),
      );
      if (saved != null) await windowManager.setBounds(saved);
      await windowManager.show();
      await windowManager.focus();
      windowManager.addListener(instance);
      debugPrint('[WIN] ready (restored=$saved)');
    } catch (e) {
      // 窗口初始化失败不阻断应用启动
      debugPrint('[WIN] 窗口初始化失败: $e');
    }
  }

  // ==================== 记忆窗口尺寸 / 位置 ====================

  Rect? _readBounds() {
    try {
      final raw = StorageService.getString(_keyBounds);
      if (raw.isEmpty) return null;
      final parts = raw.split(',');
      if (parts.length != 4) return null;
      final nums = parts.map(double.tryParse).toList();
      if (nums.any((n) => n == null)) return null;
      final rect = Rect.fromLTWH(nums[0]!, nums[1]!, nums[2]!, nums[3]!);
      // 尺寸不合法（过小 / 负数）直接丢弃
      if (rect.width < minSize.width || rect.height < minSize.height) {
        return null;
      }
      return rect;
    } catch (e) {
      debugPrint('[WIN] 读取窗口尺寸失败: $e');
      return null;
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _saveNow);
  }

  Future<void> _saveNow() async {
    try {
      // 全屏 / 最大化 / 最小化时的边界不代表用户想要的窗口尺寸
      if (await windowManager.isFullScreen()) return;
      if (await windowManager.isMaximized()) return;
      if (await windowManager.isMinimized()) return;
      final rect = await windowManager.getBounds();
      if (rect.width < minSize.width || rect.height < minSize.height) return;
      await StorageService.setString(
        _keyBounds,
        '${rect.left},${rect.top},${rect.width},${rect.height}',
      );
    } catch (e) {
      debugPrint('[WIN] 保存窗口尺寸失败: $e');
    }
  }

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMoved() => _scheduleSave();

  /// 关闭按钮被拦截（托盘已启用）时，窗口收进托盘而不是退出
  @override
  void onWindowClose() async {
    try {
      if (await windowManager.isPreventClose()) {
        await TrayService.instance.hideToTray();
      }
    } catch (e) {
      debugPrint('[WIN] 关闭拦截处理失败: $e');
    }
  }
}
