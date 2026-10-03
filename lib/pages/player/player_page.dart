import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/drama.dart';
import '../../core/models/episode.dart';
import '../../core/services/api_service.dart';
import '../../core/services/history_service.dart';
import '../../core/state/settings_provider.dart';

/// 播放模块（核心）
///
/// 1. 获取红果官方直链 MP4 播放源（无广告分片，无需过滤）
/// 2. 倍速 0.75x ~ 5x（默认值读取设置页全局配置）
/// 3. 进度拖拽 + 进度记忆、全屏播放、音量调节
/// 4. 播放完毕自动跳转下一集（官方锁定集自动停止）
class PlayerPage extends StatefulWidget {
  final Drama drama;
  final List<Episode> episodes;
  final Episode initialEpisode;

  const PlayerPage({
    super.key,
    required this.drama,
    required this.episodes,
    required this.initialEpisode,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription? _completedSub;
  Timer? _progressTimer;
  Timer? _hideTimer;

  late Episode _episode;
  double _speed = 1.0;
  double _volume = 100;
  bool _loading = true;
  String _error = '';
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _dragValue;
  bool _controlsVisible = true;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _player = Player();
    _controller = VideoController(_player);
    _volume = _player.state.volume;
    _speed = context.read<SettingsProvider>().defaultSpeed;

    _bindStreams();
    _openEpisode(widget.initialEpisode, resumeSaved: true);
  }

  void _bindStreams() {
    _player.stream.playing.listen((v) => mountedSafe(() => setState(() => _playing = v)));
    _player.stream.position.listen((v) => mountedSafe(() => setState(() => _position = v)));
    _player.stream.duration.listen((v) => mountedSafe(() => setState(() => _duration = v)));
    _player.stream.error.listen((e) {
      if (e.isNotEmpty && mounted && !_loading) {
        mountedSafe(() => setState(() => _error = '播放出错：$e'));
      }
    });
    // 播放完毕自动跳转下一集
    _completedSub = _player.stream.completed.listen((completed) {
      if (!completed || !mounted) return;
      _onEpisodeEnd();
    });
  }

  void mountedSafe(VoidCallback fn) {
    if (mounted) fn();
  }

  // ==================== 换集 / 播放源 ====================

  Future<void> _openEpisode(Episode episode, {bool resumeSaved = false}) async {
    if (!mounted) return;
    setState(() {
      _episode = episode;
      _loading = true;
      _error = '';
      _position = Duration.zero;
      _duration = Duration.zero;
      _dragValue = null;
    });
    _startProgressSaving();
    try {
      // 1) 获取官方直链 MP4 播放源
      final playUrl = await ApiService.fetchPlayUrl(
        seriesId: widget.drama.bookId,
        vid: episode.itemId,
      );
      await _player.open(Media(playUrl));
      await _player.setRate(_speed);
      // 2) 进度记忆：自动恢复上次观看位置
      if (resumeSaved) {
        final savedMs = HistoryService.progressOf(widget.drama.bookId, episode.itemId);
        if (savedMs > 0 && mounted) {
          await _player.seek(Duration(milliseconds: savedMs));
        }
      }
      if (!mounted) return;
      setState(() => _loading = false);
      _scheduleHideControls();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '播放源获取失败，请稍后重试';
      });
    }
  }

  // ==================== 进度记忆 ====================

  void _startProgressSaving() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(AppConstants.progressSaveInterval, (_) {
      if (!_playing || _position < AppConstants.progressMinKeep) return;
      HistoryService.upsert(
        widget.drama,
        episodeIndex: _episode.index,
        episodeItemId: _episode.itemId,
        positionMs: _position.inMilliseconds,
      );
    });
  }

  Future<void> _onEpisodeEnd() async {
    await HistoryService.markEpisodeFinished(
      widget.drama,
      episodeIndex: _episode.index,
    );
    final next = _episodeByIndex(_episode.index + 1);
    if (next != null && next.playable) {
      _openEpisode(next);
    } else {
      // 全部可播剧集看完（后续为官方锁定集）
      if (mounted) {
        setState(() => _playing = false);
        _showControls();
        if (next != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('官方仅开放前 3 集，后续剧集暂未解锁'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Episode? _episodeByIndex(int index) {
    for (final ep in widget.episodes) {
      if (ep.index == index) return ep;
    }
    return null;
  }

  /// 下一集可播剧集（跳过官方锁定集）
  Episode? get _nextPlayable {
    for (final ep in widget.episodes) {
      if (ep.index > _episode.index && ep.playable) return ep;
    }
    return null;
  }

  bool get _hasNextPlayable => _nextPlayable != null;

  // ==================== 控制条 ====================

  void _toggleControls() {
    if (_controlsVisible) {
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHideControls();
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _controlsVisible = false);
    });
  }

  void _togglePlay() {
    if (_playing) {
      _player.pause();
      _showControls();
    } else {
      _player.play();
      _scheduleHideControls();
    }
  }

  // ==================== 全屏 ====================

  Future<void> _toggleFullscreen() async {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      if (!PlatformCheck.isAndroid) {
        await windowManager.setFullScreen(true);
      } else {
        // Android 全屏：横屏 + 沉浸式
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } else {
      if (!PlatformCheck.isAndroid) {
        await windowManager.setFullScreen(false);
      } else {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]);
      }
    }
  }

  Future<void> _exitFullscreenIfAny() async {
    if (_fullscreen) {
      if (!PlatformCheck.isAndroid) {
        await windowManager.setFullScreen(false);
      } else {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]);
      }
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ==================== 倍速 ====================

  Future<void> _pickSpeed() async {
    _showControls();
    final defaultSpeed = context.read<SettingsProvider>().defaultSpeed;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final seed = Theme.of(sheetContext).colorScheme.primary;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text('播放倍速',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: seed)),
                    const Spacer(),
                    Text('默认 ${_speedLabel(defaultSpeed)}（设置页可改）',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(sheetContext).colorScheme.outline)),
                  ],
                ),
              ),
              ...AppConstants.playbackSpeeds.map((s) {
                final selected = s == _speed;
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: selected
                      ? Icon(Icons.check_rounded, color: seed, size: 20)
                      : const SizedBox(width: 20),
                  title: Text(_speedLabel(s)),
                  selected: selected,
                  selectedColor: seed,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    setState(() => _speed = s);
                    _player.setRate(s);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  static String _speedLabel(double s) {
    if (s == s.roundToDouble()) return '${s.toInt()}.0x';
    return '${s}x';
  }

  // ==================== 音量 ====================

  Future<void> _adjustVolume() async {
    _showControls();
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_volume > 0
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Slider(
                            value: _volume.clamp(0, 100),
                            max: 100,
                            divisions: 100,
                            label: '${_volume.round()}',
                            onChanged: (v) {
                              setSheetState(() => _volume = v);
                              _player.setVolume(v);
                              if (mounted) setState(() => _volume = v);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text('${_volume.round()}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ==================== 分集列表 ====================

  void _showEpisodeSheet() {
    _showControls();
    final seed = Theme.of(context).colorScheme.primary;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.62,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text('选择分集（共${widget.episodes.length}集）',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: seed)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.episodes.length,
                    itemBuilder: (context, index) {
                      final ep = widget.episodes[index];
                      final current = ep.index == _episode.index;
                      final locked = !ep.playable;
                      return ListTile(
                        dense: true,
                        selected: current,
                        selectedColor: seed,
                        enabled: !locked,
                        leading: current
                            ? Icon(Icons.play_arrow_rounded, color: seed, size: 20)
                            : SizedBox(
                                width: 20,
                                child: Text('${ep.index}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey)),
                              ),
                        title: Text(
                          '第${ep.index}集 ${ep.title == '第${ep.index}集' ? '' : ep.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                        trailing: locked
                            ? const Icon(Icons.lock_outline_rounded,
                                size: 16, color: Colors.grey)
                            : null,
                        onTap: locked
                            ? null
                            : () {
                                Navigator.pop(sheetContext);
                                _openEpisode(ep);
                              },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!_fullscreen) ..._buildPortraitLayout(),
            Video(
              controller: _controller,
              controls: NoVideoControls,
            ),
            if (_loading) _buildLoading(),
            if (_error.isNotEmpty) _buildError(),
            _buildControls(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPortraitLayout() {
    // 竖屏时视频区域占顶部（16:9），下方留操作区
    return [
      Align(
        alignment: Alignment.topCenter,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(color: Colors.black),
        ),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: Container(height: 4, color: Colors.black),
      ),
    ];
  }

  Widget _buildLoading() {
    return const Center(
      child: SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white54, size: 40),
          const SizedBox(height: 10),
          Text(_error, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 14),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
            onPressed: () => _openEpisode(_episode, resumeSaved: true),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final visible = _controlsVisible;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      child: IgnorePointer(
        ignoring: !visible,
        child: Column(
          children: [
            // 顶部：返回 / 标题 / 分集
            _buildTopBar(context),
            const Spacer(),
            // 中间：播放/暂停
            Center(
              child: AnimatedOpacity(
                opacity: _playing && !visible ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: IconButton(
                  iconSize: 68,
                  color: Colors.white,
                  onPressed: _loading ? null : _togglePlay,
                  icon: Icon(
                    _playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                  ),
                ),
              ),
            ),
            const Spacer(),
            // 底部：进度 + 工具栏
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 4,
        left: 6,
        right: 12,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              '${widget.drama.title} · 第${_episode.index}集',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.menu_open_rounded, color: Colors.white),
            tooltip: '分集列表',
            onPressed: _showEpisodeSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final pos = _dragValue != null
        ? Duration(milliseconds: (_dragValue! * _duration.inMilliseconds).round())
        : _position;
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 8,
        left: 14,
        right: 8,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条（可拖拽）
            Row(
              children: [
                Text(_fmt(pos),
                    style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: _duration.inMilliseconds == 0
                          ? 0
                          : (pos.inMilliseconds /
                                  _duration.inMilliseconds)
                              .clamp(0.0, 1.0),
                      max: 1,
                      onChanged: _duration.inMilliseconds == 0
                          ? null
                          : (v) => setState(() => _dragValue = v),
                      onChangeEnd: (v) {
                        final target = Duration(
                            milliseconds: (v * _duration.inMilliseconds).round());
                        _player.seek(target);
                        setState(() => _dragValue = null);
                      },
                    ),
                  ),
                ),
                Text(_fmt(_duration),
                    style: const TextStyle(color: Colors.white, fontSize: 11.5)),
              ],
            ),
            // 工具栏：倍速 / 音量 / 上一集 / 下一集 / 全屏
            Row(
              children: [
                _toolButton(context, Icons.speed_rounded, _speedLabel(_speed), _pickSpeed),
                _toolButton(
                    context,
                    _volume > 0 ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                    '音量',
                    _adjustVolume),
                _toolButton(context, Icons.skip_previous_rounded,
                    _episode.index > 1 ? '上一集' : '', _episode.index > 1
                        ? () => _openEpisode(
                            _episodeByIndex(_episode.index - 1) ?? _episode)
                        : null),
                _toolButton(
                    context,
                    Icons.skip_next_rounded,
                    _hasNextPlayable ? '下一集' : '',
                    _hasNextPlayable
                        ? () => _openEpisode(
                            _nextPlayable ?? _episode)
                        : null),
                const Spacer(),
                _toolButton(
                    context,
                    _fullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    '全屏',
                    _toggleFullscreen),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton(
      BuildContext context, IconData icon, String label, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 21),
              if (label.isNotEmpty)
                Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ==================== 生命周期 ====================

  @override
  void dispose() {
    // 退出前保存进度
    if (_position >= AppConstants.progressMinKeep &&
        _position < _duration - AppConstants.progressEndTrim) {
      HistoryService.upsert(
        widget.drama,
        episodeIndex: _episode.index,
        episodeItemId: _episode.itemId,
        positionMs: _position.inMilliseconds,
      );
    }
    _progressTimer?.cancel();
    _hideTimer?.cancel();
    _completedSub?.cancel();
    _player.dispose();
    _exitFullscreenIfAny();
    super.dispose();
  }
}

/// 平台判断（隔离 window_manager 仅桌面可用的事实）
class PlatformCheck {
  static bool get isAndroid =>
      defaultTargetPlatform == TargetPlatform.android;
}
