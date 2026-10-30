import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// YouTube 正版源的内嵌播放器（播放页 WebView 分支）
///
/// Android：WebView 加载 YouTube 官方 IFrame Player API，
/// 通过 `PlayerBridge` JS Channel 每秒回放进度/时长/播放状态，
/// Flutter 侧再转成播放页的 position/duration/playing/ended 事件，
/// 从而复用进度记忆、自动跳集、倍速等既有播放页机制。
///
/// 其他平台（本项目为 Windows）：WebView 实现不可用，展示回退面板，
/// 可一键在系统浏览器中打开对应视频继续观看。
///
/// 对外命令（由播放页经 [GlobalKey] 调用）：
/// [play] / [pause] / [seekTo] / [setRate]；就绪前调用会挂起，就绪后补发。
class YouTubeEmbedPlayer extends StatefulWidget {
  const YouTubeEmbedPlayer({
    super.key,
    required this.videoId,
    this.initialPositionMs = 0,
    this.initialRate = 1.0,
    this.onReady,
    this.onTick,
    this.onPlaying,
    this.onEnded,
    this.onError,
  });

  final String videoId;

  /// 就绪后需要恢复的进度（0 = 从头播）
  final int initialPositionMs;

  /// 就绪后需要应用的倍速
  final double initialRate;

  /// 播放器创建完成（可响应 play/seek/rate 命令）
  final VoidCallback? onReady;

  /// 每秒回放（播放位置, 总时长）
  final void Function(Duration position, Duration duration)? onTick;

  /// 播放状态变化
  final void Function(bool playing)? onPlaying;

  /// 播放完毕
  final VoidCallback? onEnded;

  /// 无法加载/播放出错（含主文档网络失败、YouTube 播放器错误码）
  final void Function(String message)? onError;

  @override
  State<YouTubeEmbedPlayer> createState() => YouTubeEmbedPlayerState();
}

class YouTubeEmbedPlayerState extends State<YouTubeEmbedPlayer> {
  WebViewController? _controller;
  bool _ready = false;

  /// 就绪前挂起的命令（就绪后一次性补发）
  int? _pendingSeekMs;
  double? _pendingRate;
  bool? _pendingPlay;

  bool _lastPlaying = false;
  bool _reportedError = false;

  /// 平台是否支持内嵌播放（仅 Android 有 WebView 实现）
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _pendingSeekMs =
        widget.initialPositionMs > 0 ? widget.initialPositionMs : null;
    _pendingRate = widget.initialRate;
    if (supported) _initWebView();
  }

  void _initWebView() {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..addJavaScriptChannel(
        'PlayerBridge',
        onMessageReceived: _onJsMessage,
      )
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (e) {
          // 只处理主文档失败（脚本/封面等子资源失败不影响起播）
          if (e.isForMainFrame != true) return;
          _reportError('无法加载 YouTube 播放器：${e.description}\n'
              '当前网络可能无法访问 YouTube');
        },
      ))
      ..loadHtmlString(
        _pageHtml(widget.videoId),
        baseUrl: 'https://www.youtube.com',
      );
    _controller = c;
  }

  // ==================== JS → Flutter ====================

  void _onJsMessage(JavaScriptMessage message) {
    if (!mounted) return;
    Map<String, dynamic> m;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map) return;
      m = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    final evt = m['evt'];
    if (evt == 'ready') {
      if (_ready) return;
      _ready = true;
      _flushPending();
      widget.onReady?.call();
      return;
    }
    if (evt == 'ended') {
      _setPlaying(false);
      widget.onEnded?.call();
      return;
    }
    if (evt == 'error') {
      final code = m['code'];
      _reportError('YouTube 播放错误（错误码 $code）。\n'
          '若持续出现，可能是当前网络对 YouTube 不可用或该视频已下架。');
      return;
    }
    if (evt == 'state') {
      _applyState(m['s']);
      return;
    }
    // 常规心跳：{t: 秒, d: 秒, s: 播放状态}
    if (m.containsKey('t') && m.containsKey('d')) {
      final pos = Duration(milliseconds: ((m['t'] as num?) ?? 0) * 1000 ~/ 1);
      final dur = Duration(milliseconds: ((m['d'] as num?) ?? 0) * 1000 ~/ 1);
      _applyState(m['s']);
      widget.onTick?.call(pos, dur);
    }
  }

  void _applyState(dynamic s) {
    final code = s is num ? s.toInt() : -99;
    // YT 状态：-1 未启动 / 0 结束 / 1 播放 / 2 暂停 / 3 缓冲 / 5 已cue
    if (code == 1 || code == 3) {
      _setPlaying(true);
    } else if (code == -1 || code == 0 || code == 2 || code == 5) {
      _setPlaying(false);
    }
  }

  void _setPlaying(bool v) {
    if (_lastPlaying == v) return;
    _lastPlaying = v;
    widget.onPlaying?.call(v);
  }

  void _reportError(String msg) {
    if (_reportedError) return;
    _reportedError = true;
    widget.onError?.call(msg);
  }

  void _flushPending() {
    final seek = _pendingSeekMs;
    final rate = _pendingRate;
    final play = _pendingPlay;
    _pendingSeekMs = null;
    _pendingRate = null;
    _pendingPlay = null;
    if (seek != null) _seekNow(seek);
    if (rate != null) _rateNow(rate);
    if (play == true) _js("jjCmd({a:'play'})");
    if (play == false) _js("jjCmd({a:'pause'})");
  }

  // ==================== 对外命令（播放页调用） ====================

  void play() {
    if (!_ready) {
      _pendingPlay = true;
      return;
    }
    _js("jjCmd({a:'play'})");
  }

  void pause() {
    if (!_ready) {
      _pendingPlay = false;
      return;
    }
    _js("jjCmd({a:'pause'})");
  }

  void seekTo(Duration target) {
    if (!_ready) {
      _pendingSeekMs = target.inMilliseconds;
      return;
    }
    _seekNow(target.inMilliseconds);
  }

  void setRate(double rate) {
    if (!_ready) {
      _pendingRate = rate;
      return;
    }
    _rateNow(rate);
  }

  void _seekNow(int ms) => _js("jjCmd({a:'seek',v:$ms})");

  void _rateNow(double r) => _js("jjCmd({a:'rate',v:$r})");

  void _js(String script) {
    final c = _controller;
    if (c == null) return;
    // 命令发出时播放器可能尚未创建，交由页面内 jjCmd 自行容错
    unawaited(c.runJavaScript(script).catchError((_) {}));
  }

  // ==================== 渲染 ====================

  @override
  Widget build(BuildContext context) {
    if (supported && _controller != null) {
      return WebViewWidget(controller: _controller!);
    }
    return _buildFallback();
  }

  /// 非 Android 平台：无 WebView 实现，提供浏览器打开回退
  Widget _buildFallback() {
    final url = 'https://www.youtube.com/watch?v=${widget.videoId}';
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_display_rounded,
                color: Colors.white54, size: 44),
            const SizedBox(height: 12),
            const Text(
              '当前平台不支持内嵌播放',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              '可在系统浏览器中打开该集视频继续观看',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
              ),
              onPressed: () => _openExternal(url),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('在浏览器中打开'),
            ),
            const SizedBox(height: 10),
            Text(
              url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  void _openExternal(String url) {
    try {
      if (Platform.isWindows) {
        Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        Process.run('open', [url]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [url]);
      }
    } catch (e) {
      debugPrint('[YT] 打开浏览器失败: $e');
    }
    // 回退面板就绪：结束加载态，交由面板自身承载交互
    widget.onReady?.call();
  }

  @override
  void dispose() {
    // WebViewController 随 WebViewWidget 销毁自动回收，无需显式关闭
    super.dispose();
  }
}

/// 播放页 HTML：div 挂载点 + IFrame API + 心跳/命令桥
///
/// `baseUrl` 为 https://www.youtube.com 时页面 origin 与 iframe 同源，
/// IFrame API 的 postMessage 校验才能通过（WebView 内嵌的关键点）。
String _pageHtml(String videoId) => '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"/>
<style>
  html, body { margin:0; padding:0; width:100%; height:100%; background:#000; overflow:hidden; }
  #p { width:100%; height:100%; }
</style>
</head>
<body>
<div id="p"></div>
<script>
var ready = false;
function bridge(o) {
  try { PlayerBridge.postMessage(JSON.stringify(o)); } catch (e) {}
}
function tick() {
  if (!ready) return;
  try {
    var p = window.yt;
    if (!p || !p.getCurrentTime) return;
    bridge({ t: p.getCurrentTime(), d: p.getDuration(), s: p.getPlayerState() });
  } catch (e) {}
}
window.onYouTubeIframeAPIReady = function () {
  try {
    window.yt = new YT.Player('p', {
      videoId: '$videoId',
      playerVars: {
        autoplay: 1,
        playsinline: 1,
        rel: 0,
        modestbranding: 1,
        enablejsapi: 1
      },
      events: {
        onReady: function () { ready = true; bridge({ evt: 'ready' }); },
        onStateChange: function (e) {
          if (e.data === 0) bridge({ evt: 'ended' });
          bridge({ evt: 'state', s: e.data });
        },
        onError: function (e) { bridge({ evt: 'error', code: e.data }); }
      }
    });
  } catch (e) {
    bridge({ evt: 'error', code: -1 });
  }
};
function jjCmd(c) {
  try {
    var p = window.yt;
    if (!p || !p.playVideo) return;
    if (c.a === 'play') p.playVideo();
    else if (c.a === 'pause') p.pauseVideo();
    else if (c.a === 'seek') p.seekTo(c.v / 1000, true);
    else if (c.a === 'rate') p.setPlaybackRate(c.v);
  } catch (e) {}
}
setInterval(tick, 1000);
var tag = document.createElement('script');
tag.src = 'https://www.youtube.com/iframe_api';
document.body.appendChild(tag);
</script>
</body>
</html>
''';
