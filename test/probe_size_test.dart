import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/play_headers.dart';

/// 比较 HEAD 与 Range GET 取分片大小是否可靠（用于同目录广告块判据）。
void main() {
  test('probe segment size methods', () async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.bytes,
      validateStatus: (c) => c != null && c < 600,
    ));
    const master =
        'https://player.yzzyssvip-36.com/20261004/560166_87be18f4/index.m3u8';
    final m = await _get(dio, master);
    final variant = m
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty && !l.startsWith('#'), orElse: () => '');
    final media = Uri.parse(master).resolve(variant).toString();
    final body = await _get(dio, media);
    final segs = body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();
    // 找 discontinuity 之后的第一个分片
    final lines = body.split('\n').map((l) => l.trim()).toList();
    var discIdx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].toUpperCase().startsWith('#EXT-X-DISCONTINUITY')) {
        discIdx = i;
      }
    }
    String segAfterDisc = '';
    for (var i = discIdx + 1; i < lines.length; i++) {
      if (lines[i].isNotEmpty && !lines[i].startsWith('#')) {
        segAfterDisc = lines[i];
        break;
      }
    }
    final targets = {
      'content-first': segs.first,
      'ad-first': segAfterDisc,
    };
    for (final e in targets.entries) {
      final url = Uri.parse(media).resolve(e.value).toString();
      // HEAD
      final h = await dio.head<void>(url,
          options: Options(headers: PlayHeaders.forUrl(master)));
      // ignore: avoid_print
      print('[${e.key}] HEAD ${h.statusCode} '
          'content-length=${h.headers.value('content-length')} '
          'headers=${h.headers.map.keys.join(',')}');
      // Range GET
      final r = await dio.get<List<int>>(url,
          options: Options(
            headers: {
              ...PlayHeaders.forUrl(master),
              'Range': 'bytes=0-0',
            },
          ));
      // ignore: avoid_print
      print('[${e.key}] RANGE ${r.statusCode} '
          'content-range=${r.headers.value('content-range')} '
          'body=${r.data?.length}');
      // 完整 GET（基准）
      final g = await dio.get<List<int>>(url,
          options: Options(headers: PlayHeaders.forUrl(master)));
      // ignore: avoid_print
      print('[${e.key}] FULL len=${g.data?.length}');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<String> _get(Dio dio, String url) async {
  final r = await dio.get<List<int>>(url,
      options: Options(headers: PlayHeaders.forUrl(url)));
  return String.fromCharCodes(r.data ?? const []);
}
