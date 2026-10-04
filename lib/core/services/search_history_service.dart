import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import 'storage_service.dart';

/// 搜索历史（本地保存，最近的在前，可单条删除/清空）
class SearchHistoryService {
  SearchHistoryService._();

  static List<String> _items = [];

  static void init() {
    _items = [];
    final raw = StorageService.getString(AppConstants.keySearchHistory);
    if (raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        _items = list
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
      }
    } catch (_) {
      // 数据损坏：按空历史处理
    }
  }

  static List<String> get items => List.unmodifiable(_items);

  /// 记录一次搜索（去重置顶，超出上限截断）
  static Future<void> add(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return;
    debugPrint('[SEARCH] history add: $kw');
    _items.remove(kw);
    _items.insert(0, kw);
    if (_items.length > AppConstants.maxSearchHistory) {
      _items = _items.sublist(0, AppConstants.maxSearchHistory);
    }
    await _persist();
  }

  /// 删除单条
  static Future<void> remove(String keyword) async {
    if (_items.remove(keyword)) await _persist();
  }

  /// 清空
  static Future<void> clear() async {
    _items = [];
    await _persist();
  }

  static Future<void> _persist() async {
    await StorageService.setString(
      AppConstants.keySearchHistory,
      jsonEncode(_items),
    );
  }
}
