import 'dart:convert';

import '../constants/app_constants.dart';
import '../models/drama.dart';
import '../models/history_entry.dart';
import 'storage_service.dart';

/// 观看历史 + 播放进度记忆（仅保存在本地，不上传服务器）
class HistoryService {
  HistoryService._();

  static List<LocalRecord> _history = [];

  static void init() {
    final raw = StorageService.getString(AppConstants.keyHistory);
    _history = _decodeList(raw);
  }

  static List<LocalRecord> get history => List.unmodifiable(_history);

  /// 取某部短剧的观看记录（含进度）
  static LocalRecord? recordOf(String bookId) {
    for (final r in _history) {
      if (r.drama.bookId == bookId) return r;
    }
    return null;
  }

  /// 取某集的播放进度（毫秒）
  static int progressOf(String bookId, String itemId) {
    final r = recordOf(bookId);
    if (r == null || r.lastEpisodeItemId != itemId) return 0;
    return r.positionMs;
  }

  /// 记录观看（新增/更新置顶）；position == null 表示保留原进度
  static Future<void> upsert(
    Drama drama, {
    required int episodeIndex,
    required String episodeItemId,
    int? positionMs,
  }) async {
    final existing = recordOf(drama.bookId);
    final keepPosition = positionMs ?? existing?.positionMs ?? 0;
    _history.removeWhere((r) => r.drama.bookId == drama.bookId);
    _history.insert(
      0,
      LocalRecord(
        drama: drama,
        lastEpisodeIndex: episodeIndex,
        lastEpisodeItemId: episodeItemId,
        positionMs: keepPosition,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (_history.length > AppConstants.maxLocalRecords) {
      _history = _history.sublist(0, AppConstants.maxLocalRecords);
    }
    await _persist();
  }

  /// 看完一集：清进度，指针移到下一集
  static Future<void> markEpisodeFinished(
    Drama drama, {
    required int episodeIndex,
  }) async {
    await upsert(drama, episodeIndex: episodeIndex, episodeItemId: '', positionMs: 0);
  }

  /// 删除单条观看记录
  static Future<void> remove(String bookId) async {
    _history.removeWhere((r) => r.drama.bookId == bookId);
    await _persist();
  }

  /// 清空全部观看记录
  static Future<void> clear() async {
    _history = [];
    await _persist();
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

  static Future<void> _persist() async {
    await StorageService.setString(
      AppConstants.keyHistory,
      jsonEncode(_history.map((r) => r.toJson()).toList()),
    );
  }
}
