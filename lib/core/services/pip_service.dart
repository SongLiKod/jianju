import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 画中画（弹窗播放）
///
/// - 播放中按 Home 键：原生侧自动进小窗，视频不中断
/// - 播放器工具栏“弹窗”按钮：手动进小窗
/// - 小窗 ↔ 全窗切换回调：播放器据此隐藏/恢复控件
class PipService {
  PipService._();

  static const MethodChannel _channel = MethodChannel('jianju/pip');

  /// 原生 → Dart：画中画状态变化
  static void Function(bool inPip)? onChanged;

  static bool _active = false;

  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> enterPip() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('enterPip');
    } catch (e) {
      debugPrint('[PIP] enter failed: $e');
    }
  }

  /// 告知原生当前是否“播放中”（Home 键自动小窗的依据）
  static Future<void> setActive(bool v) async {
    if (_active == v) return;
    _active = v;
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('setActive', v);
    } catch (_) {}
  }

  static void _attach() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPipChanged') {
        onChanged?.call(call.arguments as bool);
      }
      return null;
    });
  }

  static bool _attached = false;
  static void ensureAttached() {
    if (_attached) return;
    _attached = true;
    _attach();
  }
}
