import 'dart:convert';

import '../constants/app_constants.dart';
import '../models/drama.dart';
import '../models/history_entry.dart';
import 'storage_service.dart';

/// 本地收藏（仅保存在本地，不上传服务器）
class FavoriteService {
  FavoriteService._();

  static List<LocalRecord> _favorites = [];

  /// 启动时加载
  static void init() {
    final raw = StorageService.getString(AppConstants.keyFavorites);
    _favorites = _decodeList(raw);
  }

  static List<LocalRecord> get favorites =>
      List.unmodifiable(_favorites);

  static bool isFavorite(String bookId) =>
      _favorites.any((r) => r.drama.bookId == bookId);

  /// 收藏 / 取消收藏，返回最新状态
  static Future<bool> toggle(Drama drama, {int episodeIndex = 0, String episodeItemId = ''}) async {
    if (isFavorite(drama.bookId)) {
      _favorites.removeWhere((r) => r.drama.bookId == drama.bookId);
    } else {
      _favorites.insert(
        0,
        LocalRecord(
          drama: drama,
          lastEpisodeIndex: episodeIndex,
          lastEpisodeItemId: episodeItemId,
          positionMs: 0,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _trim();
    }
    await _persist();
    return isFavorite(drama.bookId);
  }

  static List<LocalRecord> _decodeList(String raw) {
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map(LocalRecord.fromJson)
          .where((r) => r.drama.bookId.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static void _trim() {
    if (_favorites.length > AppConstants.maxLocalRecords) {
      _favorites = _favorites.sublist(0, AppConstants.maxLocalRecords);
    }
  }

  static Future<void> _persist() async {
    await StorageService.setString(
      AppConstants.keyFavorites,
      jsonEncode(_favorites.map((r) => r.toJson()).toList()),
    );
  }
}
