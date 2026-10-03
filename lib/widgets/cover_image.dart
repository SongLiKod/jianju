import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 封面图（带缓存与占位，滑动流畅）
class CoverImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  const CoverImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholder = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
    return ClipRRect(
      borderRadius: borderRadius,
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        memCacheWidth: 400,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, _) => Container(color: placeholder),
        errorWidget: (_, _, _) => Container(
          color: placeholder,
          alignment: Alignment.center,
          child: Icon(Icons.movie_outlined,
              color: isDark ? Colors.white30 : Colors.black26),
        ),
      ),
    );
  }
}
