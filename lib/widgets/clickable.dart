import 'package:flutter/material.dart';

/// 可点击区域：补充鼠标指针与悬停反馈
///
/// [GestureDetector] 不会自动把光标切成"可点击"形态（[InkWell] 会），
/// 桌面端所有非水波纹的点击热区统一用本组件包裹，保证鼠标移上去
/// 有正确的指针提示。
class Clickable extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final Widget child;
  final MouseCursor cursor;
  final HitTestBehavior behavior;

  const Clickable({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.cursor = SystemMouseCursors.click,
    this.behavior = HitTestBehavior.deferToChild,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: behavior,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: child,
      ),
    );
  }
}
