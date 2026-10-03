import '../utils/json_utils.dart';

/// 短剧条目（首页信息流 / 搜索结果 / 详情共用）
///
/// 字段名以官方网页源为准（series_id / series_title 等），
/// 同时保留旧字段候选以兼容本地存储的历史数据。
class Drama {
  final String bookId; // series_id
  final String title;
  final String coverUrl;
  final String abstractText;
  final List<String> tags;
  final int episodeCount;
  final String readCountText; // 热度（如 "10.2万人看"）
  final String statusText; // 完结/连载
  final String categoryText;

  const Drama({
    required this.bookId,
    required this.title,
    required this.coverUrl,
    required this.abstractText,
    required this.tags,
    required this.episodeCount,
    required this.readCountText,
    required this.statusText,
    required this.categoryText,
  });

  /// 容错解析：字段名随页面结构可能不同，全部做多候选兼容
  static Drama? fromJson(Map<dynamic, dynamic> m) {
    final bookId =
        JsonUtils.s(m, const ['series_id', 'book_id', 'bookId']);
    if (bookId == null || bookId.isEmpty) return null;
    final title = JsonUtils.s(m, const [
          'series_title',
          'series_name',
          'book_name',
          'name',
          'title',
        ]) ??
        '未知短剧';

    final tags = <String>[];
    for (final key in const ['category_list', 'tags']) {
      final rawTags = m[key];
      if (rawTags is List) {
        for (final t in rawTags) {
          if (t is Map) {
            tags.add(t['name']?.toString() ?? t['tag_name']?.toString() ?? '');
          } else if (t != null) {
            tags.add(t.toString());
          }
        }
      }
    }
    final cat = m['category'];
    if (cat is String && cat.isNotEmpty) tags.insert(0, cat);

    final epCount = JsonUtils.i(
        m, const ['episode_cnt', 'chapter_count', 'episode_count', 'serial_count']);
    final read = JsonUtils.s(m, const [
      'read_count_text', 'read_count', 'read_cnt_text', 'hot_val_text',
      'heat_text', 'rank_text',
    ]);

    // 状态：episode_right_text（如"全209集"）/ series_status / creation_status
    var status = JsonUtils.s(m, const ['episode_right_text']) ?? '';
    if (status.isEmpty) {
      final raw = m['series_status'] ?? m['creation_status'];
      final code = raw?.toString();
      if (code == '0') {
        status = '完结';
      } else if (code == '1') {
        status = '连载';
      }
    }

    return Drama(
      bookId: bookId,
      title: title,
      coverUrl:
          JsonUtils.s(m, const ['series_cover', 'thumb_url', 'cover_url', 'thumb']) ??
              '',
      abstractText: JsonUtils.s(m, const [
            'series_intro',
            'abstract',
            'abstract_plain',
            'desc',
            'description',
          ]) ??
          '',
      tags: tags.where((t) => t.isNotEmpty).toSet().toList(),
      episodeCount: epCount ?? 0,
      readCountText: read ?? '',
      statusText: status,
      categoryText: cat?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'series_id': bookId,
        'series_title': title,
        'series_cover': coverUrl,
        'series_intro': abstractText,
        'category_list': tags,
        'episode_cnt': episodeCount,
        'read_count_text': readCountText,
        'episode_right_text': statusText,
        'category': categoryText,
      };

  static Drama fromJsonStored(Map<dynamic, dynamic> m) =>
      Drama.fromJson(m) ??
      Drama(
        bookId: '', title: '', coverUrl: '', abstractText: '',
        tags: const [], episodeCount: 0, readCountText: '',
        statusText: '', categoryText: '',
      );
}
