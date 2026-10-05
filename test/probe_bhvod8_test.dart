import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/play_headers.dart';

/// 打印 bhvod 清单里所有 DISCONTINUITY 及其上下文，确认标签相对 EXTINF 的位置
void main() {
  test('probe bhvod discontinuity placement', () async {
    const master =
        'https://player.yzzyssvip-36.com/20261004/560166_87be18f4/index.m3u8';
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.bytes,
      validateStatus: (c) => c != null && c < 600,
    ));
    Future<String> get(String u) async {
      final r = await dio.get<List<int>>(u,
          options: Options(headers: PlayHeaders.forUrl(u)));
      return String.fromCharCodes(r.data ?? const []);
    }

    final m = await get(master);
    final variant = m
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty && !l.startsWith('#'), orElse: () => '');
    final media = Uri.parse(master).resolve(variant).toString();
    final body = await get(media);
    final lines = body.split('\n');
    // ignore: avoid_print
    print('total lines=${lines.length} '
        'DISC=${lines.where((l) => l.trim().toUpperCase().startsWith('#EXT-X-DISCONTINUITY')).length}');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().toUpperCase().startsWith('#EXT-X-DISCONTINUITY')) {
        final from = i > 3 ? i - 3 : 0;
        final to = (i + 4 < lines.length) ? i + 4 : lines.length;
        // ignore: avoid_print
        print('--- DISC at $i ---');
        for (var j = from; j < to; j++) {
          // ignore: avoid_print
          print('${j == i ? '>>' : '  '} $j: ${lines[j].trim()}');
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
