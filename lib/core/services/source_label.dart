import 'api52_source.dart';
import 'maccms_source.dart';
import 'play_lines.dart';

/// 资源站点标注：搜索结果等处标明条目来自哪个数据源
///
/// 按条目 ID 前缀分派（与详情/播放的分派规则一致，见 `ApiService`）：
/// - `mg:<lineId>:...` → 整站站点名（如 `bsvod.com`，自定义站点为用户起的名字）
/// - `a52:...` → 52api 聚合源
/// - 无前缀 → 官方网页源
class SourceLabel {
  SourceLabel._();

  /// 官方网页源展示名
  static const String official = '官方网页源';

  /// 52api 聚合源展示名
  static const String api52 = '52api 聚合源';

  /// 条目所属资源站点名（未知 ID 回退官方）
  static String of(String bookId) {
    if (MaccmsSource.hasPrefix(bookId)) {
      final parts = bookId.split(':');
      final lineId = parts.length > 1 ? parts[1] : '';
      if (lineId.isEmpty) return official;
      return PlayLineResolver.byId(lineId)?.name ?? lineId;
    }
    if (Api52Source.hasPrefix(bookId)) return api52;
    return official;
  }
}
