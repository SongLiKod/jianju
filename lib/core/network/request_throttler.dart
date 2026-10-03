import 'dart:async';
import 'dart:math';

/// 请求节流器（内置风控节流策略）
///
/// 所有业务请求串行排队：上一个请求完成后追加「最小间隔 + 随机抖动」
/// 才会发出下一个请求，避免高频请求触发风控。
class RequestThrottler {
  RequestThrottler._();

  static final RequestThrottler instance = RequestThrottler._();

  Future<void> _tail = Future.value();

  /// 最小请求间隔
  static const Duration minInterval = Duration(milliseconds: 800);

  /// 随机抖动上限
  static const int jitterMs = 400;

  /// 排队执行一个任务
  Future<T> run<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
      await Future<void>.delayed(
        minInterval + Duration(milliseconds: Random().nextInt(jitterMs)),
      );
    });
    return completer.future;
  }
}
