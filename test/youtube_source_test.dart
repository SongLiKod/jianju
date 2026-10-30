import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/youtube_source.dart';

/// YouTube 正版源（内置目录）离线行为：
/// 别名搜索 / 详情分集 / 取链 embed 地址 / 地址解析
void main() {
  test('按剧名与别名搜索均可命中', () async {
    // 用户原始剧名（别名）
    for (final kw in ['竹下问道', '魔主齐天', '踏道为魔']) {
      final r = await YouTubeSource.search(kw);
      expect(r, isNotEmpty, reason: '别名「$kw」应命中目录');
    }
    // 正式剧名
    for (final kw in ['神竹问道', '九天镇压', '阴阳魔帝']) {
      final r = await YouTubeSource.search(kw);
      expect(r, isNotEmpty, reason: '剧名「$kw」应命中目录');
    }
    // 无关词不命中
    expect(await YouTubeSource.search('烹饪教程'), isEmpty);
  });

  test('详情：yt: 前缀 + 分集全部 playable', () async {
    final res = await YouTubeSource.detail('yt:jiutian');
    expect(res.drama, isNotNull);
    expect(res.drama!.bookId, 'yt:jiutian');
    expect(res.episodes.length, res.drama!.episodeCount);
    expect(res.episodes.every((e) => e.playable), isTrue,
        reason: '正版嵌入源全集免解锁');
    expect(res.episodes.every((e) => e.itemId.startsWith('yt:')), isTrue);
    // 未知 slug 返回空
    final bad = await YouTubeSource.detail('yt:nonexistent');
    expect(bad.drama, isNull);
  });

  test('取链：直出 YouTube embed 地址且可反解 videoId', () async {
    final detail = await YouTubeSource.detail('yt:yinyang');
    final ep = detail.episodes.first;
    final url = await YouTubeSource.play(ep.itemId);
    expect(YouTubeSource.isEmbedUrl(url), isTrue);
    expect(YouTubeSource.videoIdOf(url), ep.itemId.substring(3));
    // 非 embed 地址不误判
    expect(YouTubeSource.isEmbedUrl('https://example.com/v.mp4'), isFalse);
    expect(YouTubeSource.videoIdOf('https://example.com/v.mp4'), isNull);
    // 非法 ID 抛错
    await expectLater(
        YouTubeSource.play('yt:bad'), throwsA(isA<Exception>()));
  });

  test('目录：三部剧均有分集与封面', () {
    final all = YouTubeSource.catalog();
    expect(all.length, greaterThanOrEqualTo(3));
    for (final d in all) {
      expect(d.episodeCount, greaterThan(0));
      expect(d.coverUrl, contains('i.ytimg.com'));
      expect(d.bookId, startsWith('yt:'));
    }
  });
}
