import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/state/theme_provider.dart';
import '../core/theme/app_theme.dart';

/// 应用品牌图标：圆角方块渐变底 + 白色播放三角（矢量绘制）
///
/// 主色实时跟随主题色板（设置页切色后立即变色），形状与
/// `tool/generate_icons.ps1` 生成的位图图标一致：
/// - 圆角比例 0.22（iOS squircle 风）
/// - 三角顶点 (0.350, 0.285) / (0.350, 0.715) / (0.720, 0.500)
/// - 等宽 0.058 圆头圆角描边（位图里的磨圆处理）
///
/// 位图 `assets/icons/app_icon.png/.ico` 保留给系统托盘、桌面图标等
/// 需要固定颜色的场景；界面内一律用本组件以跟随主题色。
class BrandIcon extends StatelessWidget {
  const BrandIcon({super.key, this.size = 24, this.color});

  /// 图标边长（逻辑像素）
  final double size;

  /// 主色：不传则取当前主题色板
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final seed = color ??
        AppPalette.colors[context.watch<ThemeProvider>().colorIndex].color;
    return CustomPaint(size: Size.square(size), painter: _BrandIconPainter(seed));
  }
}

class _BrandIconPainter extends CustomPainter {
  _BrandIconPainter(this.seed);

  final Color seed;

  static double _c(double v) => v.clamp(0.0, 1.0).toDouble();

  /// 渐变亮端：提亮 + 轻微降饱和（对应位图 #3EA8FF 一端）
  static Color _lighten(Color c) {
    final h = HSVColor.fromColor(c);
    return h
        .withSaturation(_c(h.saturation * 0.8))
        .withValue(_c(h.value + 0.15))
        .toColor();
  }

  /// 渐变深端：压暗 + 加饱和（对应位图 #0047D6 一端）
  static Color _darken(Color c) {
    final h = HSVColor.fromColor(c);
    return h
        .withSaturation(_c(h.saturation * 1.05))
        .withValue(_c(h.value * 0.82))
        .toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final rect = Offset.zero & size;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(w * 0.22)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_lighten(seed), _darken(seed)],
        ).createShader(rect),
    );

    final tri = Path()
      ..moveTo(0.350 * w, 0.285 * w)
      ..lineTo(0.350 * w, 0.715 * w)
      ..lineTo(0.720 * w, 0.500 * w)
      ..close();
    canvas.drawPath(tri, Paint()..color = Colors.white);
    canvas.drawPath(
      tri,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.058
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_BrandIconPainter old) => old.seed != seed;
}
