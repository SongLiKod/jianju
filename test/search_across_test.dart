import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/models/drama.dart';
import 'package:jianju/core/services/api_service.dart';

/// 跨站搜索合并规则（离线）：同名不跨站合并 + 按来源轮流取 + 条数截断
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

  test('同名不跨站合并：每个站点各出一条，便于选源播放', () {
    final merged = ApiService.mergeSearchResults({
      0: [drama('official', '庆余年')],
      10: [drama('line1', '庆余年'), drama('line1b', '别的剧')],
      11: [drama('line2', '庆 余 年')], // 归一化后同名，跨来源仍保留
    }, 10);
    // 轮流取：第一轮 0/10/11 各一条，第二轮取 10 的第二条
    expect(merged.map((d) => d.bookId).toList(),
        ['official', 'line1', 'line2', 'line1b']);
    final sameTitle =
        merged.where((d) => d.title.replaceAll(' ', '') == '庆余年').toList();
    expect(sameTitle.length, 3, reason: '三个来源的同名剧都要出现');
  });

  test('轮流取条：首个来源不会占满 limit，后续站点仍能露出', () {
    final merged = ApiService.mergeSearchResults({
      1: [for (var i = 0; i < 10; i++) drama('off$i', '官方剧$i')],
      10: [for (var i = 0; i < 10; i++) drama('line$i', '线路剧$i')],
    }, 10);
    expect(merged.length, 10);
    expect(merged.where((d) => d.bookId.startsWith('off')).length, 5);
    expect(merged.where((d) => d.bookId.startsWith('line')).length, 5);
    // 同一轮内优先级高的来源排在前面
    expect(merged.first.bookId, 'off0');
    expect(merged.last.bookId, 'line4');
  });

  test('同一来源内部仍按归一化剧名去重（挡掉同站镜像条目）', () {
    final merged = ApiService.mergeSearchResults({
      10: [drama('line1a', '庆余年'), drama('line1b', '庆 余 年')],
    }, 10);
    expect(merged.map((d) => d.bookId).toList(), ['line1a']);
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
