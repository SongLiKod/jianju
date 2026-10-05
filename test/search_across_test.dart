import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/models/drama.dart';
import 'package:jianju/core/services/api_service.dart';

/// 跨站搜索合并规则（离线）：来源优先级拼接 + 剧名归一化去重 + 条数截断
void main() {
  Drama drama(String id, String title) => Drama(
        bookId: id,
        title: title,
        coverUrl: '',
        abstractText: '',
        tags: const [],
        episodeCount: 12,
        readCountText: '',
        statusText: '',
        categoryText: '',
      );

  test('按来源优先级升序拼接', () {
    final merged = ApiService.mergeSearchResults({
      10: [drama('c', '剧C')],
      0: [drama('a', '剧A')],
      1: [drama('b', '剧B')],
    }, 10);
    expect(merged.map((d) => d.bookId).toList(), ['a', 'b', 'c']);
  });

  test('同名条目跨站去重，保留优先级更高的一条', () {
    final merged = ApiService.mergeSearchResults({
      0: [drama('official', '庆余年')],
      10: [drama('line1', '庆余年'), drama('line1b', '别的剧')],
      11: [drama('line2', '庆 余 年')], // 归一化后同名，应被去重
    }, 10);
    expect(merged.map((d) => d.bookId).toList(), ['official', 'line1b']);
  });

  test('截断到配置条数', () {
    final merged = ApiService.mergeSearchResults({
      0: [for (var i = 0; i < 30; i++) drama('o$i', '剧$i')],
    }, 10);
    expect(merged.length, 10);

    final unlimited = ApiService.mergeSearchResults({
      0: [for (var i = 0; i < 5; i++) drama('o$i', '剧$i')],
    }, 10);
    expect(unlimited.length, 5);
  });

  test('无结果返回空列表', () {
    expect(ApiService.mergeSearchResults({}, 10), isEmpty);
    expect(ApiService.mergeSearchResults({0: []}, 10), isEmpty);
  });
}
