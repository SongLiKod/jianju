import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// 主题状态：明暗模式 + 自定义主色
///
/// 切换实时生效（notifyListeners → MaterialApp 重建），永久本地保存。
class ThemeProvider extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  int _colorIndex = 0;

  ThemeMode get mode => _mode;
  int get colorIndex => _colorIndex;

  void load() {
    switch (SettingsService.themeMode) {
      case 'light':
        _mode = ThemeMode.light;
        break;
      case 'dark':
        _mode = ThemeMode.dark;
        break;
      default:
        _mode = ThemeMode.system;
    }
    _colorIndex = SettingsService.primaryColorIndex;
  }

  /// 浅色 / 深色 / 跟随系统
  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    await SettingsService.setThemeMode(switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    });
  }

  /// 自定义主题主色（色板索引）
  Future<void> setColorIndex(int index) async {
    _colorIndex = index;
    notifyListeners();
    await SettingsService.setPrimaryColorIndex(index);
  }
}
