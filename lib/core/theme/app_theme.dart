import 'package:flutter/material.dart';

/// 预设主题色板（设置页可选，选中后 APP 全局主色实时切换）
class PaletteColor {
  final String name;
  final Color color;
  const PaletteColor(this.name, this.color);
}

class AppPalette {
  AppPalette._();

  static const List<PaletteColor> colors = [
    PaletteColor('苹果蓝', Color(0xFF0A84FF)),
    PaletteColor('靛蓝', Color(0xFF5E5CE6)),
    PaletteColor('紫罗兰', Color(0xFFBF5AF2)),
    PaletteColor('玫瑰粉', Color(0xFFFF2D55)),
    PaletteColor('珊瑚红', Color(0xFFFF453A)),
    PaletteColor('活力橙', Color(0xFFFF9F0A)),
    PaletteColor('柠檬黄', Color(0xFFFFD60A)),
    PaletteColor('清新绿', Color(0xFF30D158)),
    PaletteColor('薄荷青', Color(0xFF00C7BE)),
    PaletteColor('天空蓝', Color(0xFF64D2FF)),
    PaletteColor('岩灰', Color(0xFF8E8E93)),
    PaletteColor('咖啡棕', Color(0xFFA2845E)),
  ];
}

/// 主题构建（iOS 风：圆润卡片、大字号标题、克制分割线）
class AppTheme {
  AppTheme._();

  static ThemeData light(Color seed) => _build(seed, Brightness.light);

  static ThemeData dark(Color seed) => _build(seed, Brightness.dark);

  static ThemeData _build(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final base = isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF5F5F7),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFF5F5F7),
        foregroundColor: isDark ? Colors.white : const Color(0xFF1C1C1E),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF1C1C1E),
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        thickness: 0.5,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE9E9EB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
