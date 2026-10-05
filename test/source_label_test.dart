import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/models/drama.dart';
import 'package:jianju/core/services/source_label.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:jianju/widgets/drama_card.dart';
import 'package:jianju/widgets/poster_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  const drama = Drama(
    bookId: 'mg:bsvod.com:1234',
    title: '测试剧',
    coverUrl: '',
    abstractText: '简介',
    tags: [],
    episodeCount: 12,
    readCountText: '',
    statusText: '',
    categoryText: '',
  );

  test('按 ID 前缀标注资源站点', () {
    expect(SourceLabel.of('7648209006388857880'), SourceLabel.official);
    expect(SourceLabel.of('a52:12345'), SourceLabel.api52);
    expect(SourceLabel.of('mg:bsvod.com:1234'), 'bsvod.com');
    // 未注册线路回退为线路 id；前缀残缺回退官方
    expect(SourceLabel.of('mg:unknown.example:1'), 'unknown.example');
    expect(SourceLabel.of('mg:'), SourceLabel.official);
    expect(SourceLabel.of(''), SourceLabel.official);
  });

  testWidgets('卡片展示来源标注', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            DramaCard(drama: drama, sourceLabel: 'bsvod.com', onTap: () {}),
            SizedBox(
              height: 320,
              width: 180,
              child:
                  PosterCard(drama: drama, sourceLabel: 'bsvod.com', onTap: () {}),
            ),
          ],
        ),
      ),
    ));
    expect(find.text('来源 bsvod.com'), findsNWidgets(2));

    // 不传标注时不渲染来源行
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [DramaCard(drama: drama, onTap: () {})],
        ),
      ),
    ));
    expect(find.textContaining('来源'), findsNothing);
  });
}
