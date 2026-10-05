import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/prebuffer_service.dart';

/// 起播清单改写：标签内相对 URI 必须转绝对
///
/// 改写清单落在本地文件，mpv 按 file:// 解析相对/根相对地址，
/// AES-128 流的 `URI="/key.key"` 会指到盘符根目录导致取不到密钥，
/// 表现为「播放出错：Failed to recognize file format」。
void main() {
  final base =
      Uri.parse('https://vod1.maowushi.com/20261004/x/3093kb/hls/index.m3u8');

  test('根相对 key 地址转绝对', () {
    expect(
      PrebufferService.absolutizeTag(
        '#EXT-X-KEY:METHOD=AES-128,URI="/20261004/x/key.key",'
        'IV=0x00000000000000000000000000000000',
        base,
      ),
      '#EXT-X-KEY:METHOD=AES-128,'
      'URI="https://vod1.maowushi.com/20261004/x/key.key",'
      'IV=0x00000000000000000000000000000000',
    );
  });

  test('同目录相对地址按清单所在目录解析', () {
    expect(
      PrebufferService.absolutizeTag('#EXT-X-MAP:URI="init.mp4"', base),
      '#EXT-X-MAP:URI="https://vod1.maowushi.com/20261004/x/3093kb/hls/init.mp4"',
    );
  });

  test('绝对地址与无 URI 标签原样保留', () {
    const abs =
        '#EXT-X-KEY:METHOD=AES-128,URI="https://cdn.example.com/k.key"';
    expect(PrebufferService.absolutizeTag(abs, base), abs);
    expect(PrebufferService.absolutizeTag('#EXTM3U', base), '#EXTM3U');
    expect(
        PrebufferService.absolutizeTag('#EXT-X-KEY:METHOD=NONE', base),
        '#EXT-X-KEY:METHOD=NONE');
    expect(PrebufferService.absolutizeTag('#EXT-X-ENDLIST', base),
        '#EXT-X-ENDLIST');
  });
}
