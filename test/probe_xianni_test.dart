import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/api_service.dart';
import 'package:jianju/core/services/play_headers.dart';
import 'package:jianju/core/services/play_lines.dart';
import 'package:jianju/core/services/settings_service.dart';
import 'package:jianju/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 线上诊断：复现《仙逆》第 161 集「Failed to recognize file format」
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    PlayLineResolver.clearCaches();
  });

  test('probe 仙逆 ep161 取链 + 直链内容体检', () async {
    // ignore: avoid_print
    print('dataSource=${SettingsService.dataSource} '
        'pinned=${SettingsService.pinnedLineId}');

    String title = '仙逆';
    String? seriesId;
    var vid = '';
    final hits = await ApiService.search(keyword: '仙逆');
    // ignore: avoid_print
    print('search hits=${hits.length}');
    for (final d in hits) {
      // ignore: avoid_print
      print('  - "${d.title}" id=${d.bookId} eps=${d.episodeCount}');
    }
    final pick = hits.firstWhere(
      (d) => d.title.contains('仙逆') && d.episodeCount >= 161,
      orElse: () => hits.isEmpty ? throw Exception('搜索无结果') : hits.first,
    );
    title = pick.title;
    seriesId = pick.bookId;
    // ignore: avoid_print
    print('picked "$title" id=$seriesId eps=${pick.episodeCount}');

    final detail = await ApiService.fetchDetail(seriesId);
    // ignore: avoid_print
    print('episodes=${detail.episodes.length} drama=${detail.drama?.title}');
    if (detail.episodes.length >= 161) {
      vid = detail.episodes[160].itemId;
      // ignore: avoid_print
      print('ep161 vid=$vid');
    } else {
      // ignore: avoid_print
      print('详情分集不足 161，走线路按标题解析');
    }

    final url = await ApiService.fetchPlayUrl(
      seriesId: seriesId,
      vid: vid.isEmpty ? 'probe-$seriesId-161' : vid,
      title: title,
      episodeIndex: 161,
    );
    // ignore: avoid_print
    print('RESOLVED line=${PlayLineResolver.lastUsedLine?.id} '
        'lineName=${PlayLineResolver.lastUsedLine?.name}');
    // ignore: avoid_print
    print('RESOLVED url=$url');

    final headers = PlayHeaders.forUrl(url);
    // ignore: avoid_print
    print('HEADERS ${Uri.parse(url).host} $headers');

    final client = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.bytes,
      headers: headers,
      validateStatus: (c) => c != null && c < 600,
    ));
    final resp = await client.get<List<int>>(url);
    final body = resp.data ?? const <int>[];
    final ctype = resp.headers.value(Headers.contentTypeHeader);
    // ignore: avoid_print
    print('HTTP ${resp.statusCode} content-type=$ctype '
        'bytes=${body.length} finalUrl=${resp.realUri}');
    final head = String.fromCharCodes(body.take(400));
    // ignore: avoid_print
    print('BODY-HEAD: ${head.replaceAll(RegExp(r'\s+'), ' ')}');
    // ignore: avoid_print
    print('looksMedia=${!head.trimLeft().startsWith('<')} '
        'startsWithExtM3U=${head.trimLeft().startsWith('#EXTM3U')}');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
