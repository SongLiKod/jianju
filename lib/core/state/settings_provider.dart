import 'package:flutter/foundation.dart';

import '../services/settings_service.dart';

/// 全局设置状态（默认倍速 / 数据源 / 52api apikey / 播放线路）
class SettingsProvider extends ChangeNotifier {
  double _defaultSpeed = 1.0;
  String _dataSource = 'web';
  String _apiKey52 = '';
  String _pinnedLineId = '';

  double get defaultSpeed => _defaultSpeed;

  String get dataSource => _dataSource;

  String get apiKey52 => _apiKey52;

  /// 手动锁定的播放线路（'' = 自动选择最快线路）
  String get pinnedLineId => _pinnedLineId;

  bool get hasApi52Key => _apiKey52.isNotEmpty;

  void load() {
    _defaultSpeed = SettingsService.defaultSpeed;
    _dataSource = SettingsService.dataSource;
    _apiKey52 = SettingsService.apiKey52;
    _pinnedLineId = SettingsService.pinnedLineId;
  }

  /// 修改全局默认倍速（播放器打开视频时自动加载）
  Future<void> setDefaultSpeed(double speed) async {
    _defaultSpeed = speed;
    notifyListeners();
    await SettingsService.setDefaultSpeed(speed);
  }

  /// 切换数据源（web=官方网页源 / api52=52api 红果源）
  Future<void> setDataSource(String source) async {
    _dataSource = source;
    notifyListeners();
    await SettingsService.setDataSource(source);
  }

  /// 保存 52api apikey（空串即清除）
  Future<void> setApiKey52(String key) async {
    _apiKey52 = key.trim();
    notifyListeners();
    await SettingsService.setApiKey52(key);
  }

  /// 切换播放线路（'' = 自动选择最快，否则锁定指定线路）
  Future<void> setPinnedLine(String lineId) async {
    _pinnedLineId = lineId.trim();
    notifyListeners();
    await SettingsService.setPinnedLine(lineId);
  }
}
