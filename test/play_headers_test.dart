import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/constants/api_constants.dart';
import 'package:jianju/core/services/play_headers.dart';

/// 播放直链请求头：浏览器 UA 兜底 + 来源 Referer 登记 + 失败自检边界
///
/// 背景：mpv 裸连第三方 CDN（curl/mpv UA、无 Referer）会被防盗链 403 拒掉，
/// 播放页报 `播放出错：Failed to open ...`。
void main() {
  test('未登记来源时仍带浏览器 UA、不带 Referer', () {
    final h = PlayHeaders.forUrl('https://cdn-a.example.com/1/index.m3u8');
    expect(h['User-Agent'], ApiConstants.browserUserAgent);
    expect(h.containsKey('Referer'), isFalse);
  });

  test('登记来源后补 Referer', () {
    const url = 'https://cdn-b.example.com/1/index.m3u8';
    PlayHeaders.register(url, referer: 'https://line.example.com/');
    final h = PlayHeaders.forUrl(url);
    expect(h['Referer'], 'https://line.example.com/');
    expect(h['User-Agent'], ApiConstants.browserUserAgent);
  });

  test('登记只作用于该地址', () {
    const withRef = 'https://cdn-c.example.com/1/index.m3u8';
    PlayHeaders.register(withRef, referer: 'https://line.example.com/');
    expect(PlayHeaders.forUrl('https://cdn-d.example.com/1/index.m3u8')
        .containsKey('Referer'),
        isFalse);
  });

  test('未登记 Referer 的来源只落 UA（不写空 Referer）', () {
    const url = 'https://cdn-e.example.com/1/index.mp4';
    PlayHeaders.register(url);
    final h = PlayHeaders.forUrl(url);
    expect(h['User-Agent'], ApiConstants.browserUserAgent);
    expect(h.containsKey('Referer'), isFalse);
  });

  test('本地文件与空地址不发起自检', () async {
    expect(await PlayHeaders.diagnose(''), '');
    expect(await PlayHeaders.diagnose('/data/local/tmp/1.ts'), '');
    expect(await PlayHeaders.diagnose('file:///sdcard/1.mp4'), '');
  });
}
