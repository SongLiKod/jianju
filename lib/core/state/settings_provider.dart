import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../services/play_lines.dart';
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
  int _searchLimit = AppConstants.defaultSearchLimit;
  bool _lineQualityFirst = AppConstants.defaultLineQualityFirst;
  bool _stripAds = AppConstants.defaultStripAds;
  String _searchScope = AppConstants.defaultSearchScope;
  final Set<String> _disabledSites = <String>{};
  final Set<String> _pickedSites = <String>{};

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

  /// 跨站搜索最多展示的条数
  int get searchLimit => _searchLimit;

  /// 路径 A：清晰度优先选线路
  bool get lineQualityFirst => _lineQualityFirst;

  /// 播放去广告开关（关闭后原样起播）
  bool get stripAds => _stripAds;

  /// 搜索范围：跨站 / 本站 / 指定站点
  String get searchScope => _searchScope;

  /// 「指定站点」搜索勾选的站点 id
  Set<String> get pickedSites => Set.unmodifiable(_pickedSites);

  /// 已停用的站点 id（首页切换列表与搜索均不出现）
  Set<String> get disabledSites => Set.unmodifiable(_disabledSites);

  bool isSiteEnabled(String lineId) => !_disabledSites.contains(lineId);

  /// 启用中的站点数（至少保留 1 个）
  int get enabledSiteCount {
    var n = 0;
    for (final line in PlayLineResolver.allLines) {
      if (!_disabledSites.contains(line.id)) n++;
    }
    return n;
  }

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
    _searchLimit = SettingsService.searchLimit;
    _lineQualityFirst = SettingsService.lineQualityFirst;
    _stripAds = SettingsService.stripAds;
    _searchScope = SettingsService.searchScope;
    _disabledSites
      ..clear()
      ..addAll(_idSet(SettingsService.disabledSitesRaw));
    _pickedSites
      ..clear()
      ..addAll(_idSet(SettingsService.pickedSearchSitesRaw));
  }

  static Set<String> _idSet(String raw) {
    if (raw.trim().isEmpty) return <String>{};
    try {
      final list = jsonDecode(raw);
      if (list is! List) return <String>{};
      return {
        for (final e in list)
          if (e.toString().trim().isNotEmpty) e.toString().trim(),
      };
    } catch (_) {
      return <String>{};
    }
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

  /// 路径 A：清晰度优先选线路（下次解析线路时生效）
  Future<void> setLineQualityFirst(bool v) async {
    debugPrint('[SET] lineQualityFirst -> $v');
    _lineQualityFirst = v;
    notifyListeners();
    await SettingsService.setLineQualityFirst(v);
  }

  /// 修改跨站搜索结果条数
  Future<void> setSearchLimit(int v) async {
    debugPrint('[SET] searchLimit -> $v');
    _searchLimit = v;
    notifyListeners();
    await SettingsService.setSearchLimit(v);
  }

  /// 播放去广告开关
  Future<void> setStripAds(bool v) async {
    debugPrint('[SET] stripAds -> $v');
    _stripAds = v;
    notifyListeners();
    await SettingsService.setStripAds(v);
  }

  /// 搜索范围（跨站 / 本站 / 指定站点）
  Future<void> setSearchScope(String scope) async {
    if (!AppConstants.searchScopeOptions.contains(scope)) return;
    debugPrint('[SET] searchScope -> $scope');
    _searchScope = scope;
    notifyListeners();
    await SettingsService.setSearchScope(scope);
  }

  /// 「指定站点」搜索勾选集合
  Future<void> setPickedSites(Set<String> ids) async {
    _pickedSites
      ..clear()
      ..addAll(ids);
    notifyListeners();
    await SettingsService.setPickedSearchSitesRaw(jsonEncode(_pickedSites.toList()));
  }

  /// 启用/停用站点（停用后首页切换不显示、搜索与播放取链不再使用）
  Future<void> setSiteEnabled(String lineId, bool enabled) async {
    if (enabled) {
      _disabledSites.remove(lineId);
    } else {
      if (enabledSiteCount <= 1) return; // 至少保留一个可用站点
      _disabledSites.add(lineId);
    }
    debugPrint('[SET] site $lineId -> ${enabled ? 'on' : 'off'}');
    notifyListeners();
    await SettingsService.setDisabledSitesRaw(jsonEncode(_disabledSites.toList()));
  }

  /// 修改全局默认倍速（播放器打开视频时自动加载）
  Future<void> setDefaultSpeed(double speed) async {
    _defaultSpeed = speed;
    notifyListeners();
    await SettingsService.setDefaultSpeed(speed);
  }

  /// 切换数据源（web=官方网页源 / api52=52api 聚合源）
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
