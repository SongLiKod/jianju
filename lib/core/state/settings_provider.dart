import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// 播放器全局默认配置状态（默认倍速等）
class SettingsProvider extends ChangeNotifier {
  double _defaultSpeed = 1.0;

  double get defaultSpeed => _defaultSpeed;

  void load() {
    _defaultSpeed = SettingsService.defaultSpeed;
  }

  /// 修改全局默认倍速（播放器打开视频时自动加载）
  Future<void> setDefaultSpeed(double speed) async {
    _defaultSpeed = speed;
    notifyListeners();
    await SettingsService.setDefaultSpeed(speed);
  }
}
