import 'drama.dart';

/// 观看历史 / 收藏 共用的本地记录（只存本地，不上传）
class LocalRecord {
  final Drama drama;
  final int lastEpisodeIndex; // 观看到第几集（收藏时同历史）
  final String lastEpisodeItemId;
  final int positionMs; // 该集播放进度（毫秒）
  final int updatedAt; // 毫秒时间戳

  const LocalRecord({
    required this.drama,
    required this.lastEpisodeIndex,
    required this.lastEpisodeItemId,
    required this.positionMs,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'drama': drama.toJson(),
        'last_episode_index': lastEpisodeIndex,
        'last_episode_item_id': lastEpisodeItemId,
        'position_ms': positionMs,
        'updated_at': updatedAt,
      };

  static LocalRecord fromJson(Map<dynamic, dynamic> m) {
    return LocalRecord(
      drama: Drama.fromJsonStored((m['drama'] as Map?) ?? const {}),
      lastEpisodeIndex: (m['last_episode_index'] as num?)?.toInt() ?? 0,
      lastEpisodeItemId: m['last_episode_item_id']?.toString() ?? '',
      positionMs: (m['position_ms'] as num?)?.toInt() ?? 0,
      updatedAt: (m['updated_at'] as num?)?.toInt() ?? 0,
    );
  }
}
