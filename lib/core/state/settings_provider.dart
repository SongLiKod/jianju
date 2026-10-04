import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../services/settings_service.dart';

/// 全局设置状态（默认倍速 / 数据源 / 52api apikey / 播放线路）
class SettingsProvider extends ChangeNotifier {
  double _defaultSpeed = 1.0;
  String _dataSource = 'web';
  String _apiKey52 = '';
  String _pinnedLineId = '';
  bool _preloadNext = AppConstants.defaultPreloadNext;
  int _preloadLeadSec = AppConstants.defaultPreloadLeadSec;
  int _bufferSecs = AppConstants.defaultBufferSecs;
  bool _slimProgress = AppConstants.defaultSlimProgress;

  double get defaultSpeed => _defaultSpeed;

  String get dataSource => _dataSource;

  String get apiKey52 => _apiKey52;

  /// 手动锁定的播放线路（'' = 自动选择最快线路）
  String get pinnedLineId => _pinnedLineId;

  /// 预载下一集开关（本集结尾前提前解析下一集）
  bool get preloadNext => _preloadNext;

  /// 预载提前量（距结尾秒数）
  int get preloadLeadSec => _preloadLeadSec;

  /// 网络缓冲秒数
  int get bufferSecs => _bufferSecs;

  /// 底部细进度条常显
  bool get slimProgress => _slimProgress;

  bool get hasApi52Key => _apiKey52.isNotEmpty;

  void load() {
    _defaultSpeed = SettingsService.defaultSpeed;
    _dataSource = SettingsService.dataSource;
    _apiKey52 = SettingsService.apiKey52;
    _pinnedLineId = SettingsService.pinnedLineId;
    _preloadNext = SettingsService.preloadNext;
    _preloadLeadSec = SettingsService.preloadLeadSec;
    _bufferSecs = SettingsService.bufferSecs;
    _slimProgress = SettingsService.slimProgress;
  }

  // ==================== 播放体验 ====================

  Future<void> setPreloadNext(bool v) async {
    debugPrint('[SET] preloadNext -> $v');
    _preloadNext = v;
    notifyListeners();
    await SettingsService.setPreloadNext(v);
  }

  Future<void> setPreloadLeadSec(int v) async {
    debugPrint('[SET] preloadLeadSec -> ${v}s');
    _preloadLeadSec = v;
    notifyListeners();
    await SettingsService.setPreloadLeadSec(v);
  }

  Future<void> setBufferSecs(int v) async {
    debugPrint('[SET] bufferSecs -> ${v}s');
    _bufferSecs = v;
    notifyListeners();
    await SettingsService.setBufferSecs(v);
  }

  Future<void> setSlimProgress(bool v) async {
    debugPrint('[SET] slimProgress -> $v');
    _slimProgress = v;
    notifyListeners();
    await SettingsService.setSlimProgress(v);
  }

  /// 修改全局默认倍速（播放器打开视频时自动加载）
  Future<void> setDefaultSpeed(double speed) async {
    _defaultSpeed = speed;
    notifyListeners();
    await SettingsService.setDefaultSpeed(speed);
  }

  /// 切换数据源（web=官方网页源 / api52=52api 红果源）
  Future<void> setDataSource(String source) async {
    debugPrint('[SRC] setDataSource $_dataSource -> $source');
    _dataSource = source;
    notifyListeners();
    await SettingsService.setDataSource(source);
  }

  /// 保存 52api apikey（空串即清除）
  Future<void> setApiKey52(String key) async {
    debugPrint('[SRC] setApiKey52 len=${key.trim().length}');
    _apiKey52 = key.trim();
    // 清除 apikey 时若当前数据源就是 52api：自动切回官方网页源，
    // 避免「已选中 52api 却静默走官方」的误导状态
    final dropToWeb = _apiKey52.isEmpty &&
        _dataSource == AppConstants.dataSourceApi52;
    if (dropToWeb) _dataSource = AppConstants.dataSourceWeb;
    notifyListeners();
    await SettingsService.setApiKey52(key);
    if (dropToWeb) {
      await SettingsService.setDataSource(AppConstants.dataSourceWeb);
    }
  }

  /// 切换播放线路（'' = 自动选择最快，否则锁定指定线路）
  Future<void> setPinnedLine(String lineId) async {
    debugPrint('[SRC] setPinnedLine -> ${lineId.isEmpty ? 'auto' : lineId}');
    _pinnedLineId = lineId.trim();
    notifyListeners();
    await SettingsService.setPinnedLine(lineId);
  }
}
