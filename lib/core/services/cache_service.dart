import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// 图片缓存管理（查看大小 / 一键清除）
class CacheService {
  CacheService._();

  static const _cacheKey = 'libCachedImageData';

  /// 图片缓存目录大小（字节）
  static Future<int> imageSizeBytes() async {
    try {
      final dir = await getTemporaryDirectory();
      final cacheDir = Directory('${dir.path}/$_cacheKey');
      if (!await cacheDir.exists()) return 0;
      var total = 0;
      await for (final entity
          in cacheDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// 一键清除图片缓存
  static Future<void> clearImageCache() async {
    await DefaultCacheManager().emptyCache();
    try {
      final dir = await getTemporaryDirectory();
      final cacheDir = Directory('${dir.path}/$_cacheKey');
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
