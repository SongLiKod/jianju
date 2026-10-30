import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/play_lines.dart';
import 'package:jianju/core/services/site_discovery_service.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:jianju/pages/discovery/site_discovery_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在线发现页：空态、发现结果的呈现与勾选、加入站点库、订阅导入、查找中可停止。
/// 全部走注入的假实现（debugDiscover / debugFetchText / debugProbe），
/// 不发起真实网络请求。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    PlayLineResolver.resetCustomLinesForTest();
    SiteDiscoveryService.debugDiscover = null;
    SiteDiscoveryService.debugFetchText = null;
    SiteDiscoveryService.debugProbe = null;
  });

  tearDown(() {
    SiteDiscoveryService.debugDiscover = null;
    SiteDiscoveryService.debugFetchText = null;
    SiteDiscoveryService.debugProbe = null;
  });

  Future<void> pumpPage(WidgetTester tester) async {
    // 放大视口：控制区 + 若干候选卡片要一次建出来
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SiteDiscoveryPage()));
    await tester.pump();
  }

  SiteCandidate okCandidate(String base, {String? sample}) => SiteCandidate(
        base: base,
        host: Uri.parse(base).host,
        source: DiscoverySource.engine,
      )
        ..status = CandidateStatus.ok
        ..mode = PlayLineMode.api
        ..latencyMs = 130
        ..sampleTitle = sample ?? '庆余年'
        ..selected = true;

  testWidgets('空态：给出入口提示与来源开关，未勾选时加入按钮禁用', (tester) async {
    await pumpPage(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('输入关键词开始查找，或点右上角从订阅地址导入'), findsOneWidget);
    expect(find.text('开始查找'), findsOneWidget);
    expect(find.text('搜索引擎'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('友链扩展'), findsOneWidget);
    expect(find.byIcon(Icons.link_rounded), findsOneWidget);

    final addBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '勾选可用站点后加入'));
    expect(addBtn.onPressed, isNull);
  });

  testWidgets('发现结果：展示来源、耗时/样例，勾选后加入站点库', (tester) async {
    SiteDiscoveryService.debugDiscover = (req) async {
      expect(req.keyword, '短剧');
      expect(req.useEngine && req.useGithub && req.useFriend, isTrue);
      return [
        okCandidate('https://new1.com'),
        SiteCandidate(
            base: 'https://dead.com',
            host: 'dead.com',
            source: DiscoverySource.github)
          ..status = CandidateStatus.failed
          ..failReason = '接口无响应',
        SiteCandidate(
            base: 'https://bsvod.com',
            host: 'bsvod.com',
            source: DiscoverySource.friend)
          ..status = CandidateStatus.known,
      ];
    };

    await pumpPage(tester);
    await tester.tap(find.text('开始查找'));
    await tester.pumpAndSettle();

    expect(find.text('new1.com'), findsOneWidget);
    expect(find.textContaining('样例：庆余年'), findsOneWidget);
    expect(find.textContaining('130ms'), findsOneWidget);
    expect(find.textContaining('接口无响应'), findsOneWidget);
    expect(find.text('已存在'), findsOneWidget);
    expect(find.textContaining('候选 3 个 · 可用 1 个 · 已存在 1 个'), findsOneWidget);

    // 只有探测通过的站点可勾选，且默认已选
    final boxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(boxes.length, 3);
    expect(boxes.where((b) => b.value == true).length, 1);
    expect(boxes.where((b) => b.enabled ?? false).length, 1);

    await tester.tap(find.widgetWithText(FilledButton, '加入所选（1）'));
    await tester.pumpAndSettle();

    expect(PlayLineResolver.customLines.length, 1);
    final added = PlayLineResolver.customLines.single;
    expect(added.base, 'https://new1.com');
    expect(added.mode, PlayLineMode.api);
    expect(added.isCustom, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('订阅地址导入：解析后走探测，通过即可加入', (tester) async {
    SiteDiscoveryService.debugFetchText = (url) async {
      expect(url, 'https://sub.com/list.json');
      return '{"sites":[{"name":"我的源","base":"https://sub.myvod.com"}]}';
    };
    SiteDiscoveryService.debugProbe = (base) async {
      expect(base, 'https://sub.myvod.com');
      return const AutoProbeResult(
          mode: PlayLineMode.api, latencyMs: 66, sampleTitle: '庆余年');
    };

    await pumpPage(tester);
    await tester.tap(find.byIcon(Icons.link_rounded));
    await tester.pumpAndSettle();

    final field = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(field, 'https://sub.com/list.json');
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();

    expect(find.text('我的源'), findsOneWidget);
    expect(find.textContaining('66ms'), findsOneWidget);
    expect(find.textContaining('从订阅地址解析出 1 个候选'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '加入所选（1）'));
    await tester.pumpAndSettle();

    expect(PlayLineResolver.customLines.length, 1);
    expect(PlayLineResolver.customLines.single.name, '我的源');
    expect(PlayLineResolver.customLines.single.base, 'https://sub.myvod.com');
    expect(tester.takeException(), isNull);
  });

  testWidgets('订阅地址拉取失败时在弹窗内提示，不写入任何候选', (tester) async {
    SiteDiscoveryService.debugFetchText = (url) async => null;

    await pumpPage(tester);
    await tester.tap(find.byIcon(Icons.link_rounded));
    await tester.pumpAndSettle();

    final field = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(field, 'https://dead.com/list.json');
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();

    expect(find.textContaining('地址无响应或返回为空'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(PlayLineResolver.customLines, isEmpty);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('输入关键词开始查找，或点右上角从订阅地址导入'), findsOneWidget);
  });

  testWidgets('查找中显示停止按钮，停止后回到空态', (tester) async {
    final gate = Completer<List<SiteCandidate>>();
    SiteDiscoveryService.debugDiscover = (_) => gate.future;

    await pumpPage(tester);
    await tester.tap(find.text('开始查找'));
    await tester.pump();

    expect(find.text('查找中…'), findsOneWidget);
    expect(find.text('停止'), findsOneWidget);
    expect(find.text('正在从公网查找候选站点…'), findsOneWidget);

    await tester.tap(find.text('停止'));
    await tester.pump();
    expect(find.text('输入关键词开始查找，或点右上角从订阅地址导入'), findsOneWidget);
    expect(find.text('开始查找'), findsOneWidget);

    gate.complete([]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
