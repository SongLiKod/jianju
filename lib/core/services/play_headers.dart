import 'dart:async';
import 'dart:io';

import '../constants/api_constants.dart';

/// 播放直链请求头（防盗链适配）
///
/// 第三方线路/整站源给出的 m3u8 常按 UA、Referer 防盗链，而 mpv 默认用
/// curl/mpv UA、不带 Referer 直连 CDN，容易被 403/超时拒掉——播放页表现为
/// `播放出错：Failed to open ...`。取链时登记来源站点，播放器与
/// 预缓存下载统一补齐浏览器请求头，让 mpv 的请求与解析时的网页请求一致。
class PlayHeaders {
  PlayHeaders._();

  /// 按直链登记的来源请求头（取链时写入，量很小，超限整体清空）
  static final Map<String, Map<String, String>> _byUrl = {};

  /// 登记直链来源：[referer] 为来源站点首页（`${base}/`）
  static void register(String url, {String? referer}) {
    if (url.isEmpty) return;
    if (_byUrl.length > 64) _byUrl.clear();
    _byUrl[url] =
        referer == null ? const <String, String>{} : {'Referer': referer};
  }

  /// 请求 [url] 应携带的请求头：浏览器 UA + 来源 Referer
  static Map<String, String> forUrl(String url) {
    final out = <String, String>{
      'User-Agent': ApiConstants.browserUserAgent,
    };
    final ref = _byUrl[url];
    if (ref != null) out.addAll(ref);
    return out;
  }

  /// 打不开时的自检：用与播放器一致的请求头拉一次首字节，返回中文原因
  /// （如「HTTP 403 拒绝访问（防盗链）」），判断不了时返回空串。
  ///
  /// 只在播放失败后调用，不占用起播时间；本地文件/非法地址直接返回空。
  static Future<String> diagnose(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      return '';
    }
    final client =
        HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(uri);
      for (final e in forUrl(url).entries) {
        req.headers.set(e.key, e.value);
      }
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final code = resp.statusCode;
      final bytes = <int>[];
      await for (final chunk in resp) {
        bytes.addAll(chunk);
        if (bytes.length >= 2048) break;
      }
      if (code == HttpStatus.forbidden || code == HttpStatus.unauthorized) {
        return '自检：HTTP $code 拒绝访问（防盗链或链接失效）';
      }
      if (code == HttpStatus.notFound || code == HttpStatus.gone) {
        return '自检：HTTP $code 地址已失效';
      }
      if (code >= 400) return '自检：HTTP $code 无法访问';
      // 首字节判断：m3u8 必须是清单头，返回 HTML 说明被拦截/跳到错误页
      final head = String.fromCharCodes(bytes.take(2048)).trimLeft();
      if (head.startsWith('<')) return '自检：返回的不是视频（疑似拦截页）';
      if (head.isNotEmpty && !head.startsWith('#EXTM3U') && _looksLikeUrl(url)) {
        return '自检：返回内容不是有效清单';
      }
      return '自检：地址可达，播放器无法打开（可点重试或换线路）';
    } catch (e) {
      if (e is TimeoutException) return '自检：连接超时';
      if (e is HandshakeException || e is SocketException) {
        return '自检：网络或证书异常，无法连接服务器';
      }
      if (e is HttpException) return '自检：响应异常（${e.message}）';
      return '自检：无法连接';
    } finally {
      client.close(force: true);
    }
  }

  static bool _looksLikeUrl(String url) =>
      Uri.tryParse(url)?.path.toLowerCase().endsWith('.m3u8') ?? false;
}
