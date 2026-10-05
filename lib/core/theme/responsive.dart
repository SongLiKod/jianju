import 'package:flutter/material.dart';

/// 响应式布局断点与通用尺寸（手机 / 窄窗口 / 桌面窗口自动切换）
///
/// 宽窗口（≥ [wideBreakpoint]）走桌面壳：左侧常驻导航栏 + 居中限宽内容；
/// 窄窗口保持手机端底部悬浮导航条布局，移动端表现完全不变。
class AppLayout {
  AppLayout._();

  /// 启用桌面壳（左侧常驻导航栏）的最小窗口宽度
  static const double wideBreakpoint = 1000;

  /// 桌面侧边栏宽度（与 AppSidebar 保持一致）
  static const double sidebarWidth = 216;

  /// 桌面端二级页内容最大宽度（超出居中，避免整行文字拉满 1920px）
  static const double contentMaxWidth = 960;

  /// 桌面端滚动区左右留白
  static const double wideGutter = 24;

  /// 桌面端滚动区底部留白（无悬浮导航条）
  static const double wideBottom = 40;

  /// 宽窗口（桌面壳布局）
  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wideBreakpoint;

  /// 海报网格列数：按可用宽度自动增减，单卡宽度稳定在 160~240 之间
  ///
  /// [availableWidth] 为实际可用宽度（建议在 LayoutBuilder 里取约束宽度），
  /// [gutter] 为该网格自身的左右留白。
  static int columnsFor(
    double availableWidth, {
    double targetWidth = 190,
    int min = 3,
    int max = 8,
    double gutter = 0,
  }) {
    final usable = availableWidth - gutter * 2;
    if (!usable.isFinite || usable <= 0) return min;
    return (usable / targetWidth).floor().clamp(min, max);
  }

  /// 滚动内容底部留白：宽窗口没有悬浮导航条，直接留固定空隙
  ///
  /// [mobileInset] 为手机端在安全区之上的额外留白（悬浮导航条高度）。
  static double scrollBottom(BuildContext context, {double mobileInset = 96}) =>
      isWide(context)
          ? wideBottom
          : MediaQuery.paddingOf(context).bottom + mobileInset;
}

/// 底部弹层宽度约束：宽窗口下限宽居中，避免弹层横跨整个窗口
///
/// 用法：`showModalBottomSheet(context: ..., constraints: sheetConstraints(context))`
BoxConstraints? sheetConstraints(BuildContext context) =>
    AppLayout.isWide(context) ? const BoxConstraints(maxWidth: 460) : null;

/// 桌面端限宽容器：宽窗口下水平居中并限制最大宽度，窄窗口原样返回
///
/// 用于设置 / 详情 / 收藏等文本型二级页，避免内容被拉伸到整屏宽度。
class CenteredContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const CenteredContent({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.contentMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (!AppLayout.isWide(context)) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        // 宽窗口下强制吃满限宽，保证 List / Column 结构宽度一致
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
