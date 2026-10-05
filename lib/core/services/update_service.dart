import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 一次检查到的可更新信息（GitHub Release）
class UpdateInfo {
  final String version;
  final String notes;
  final String? apkUrl;
  final int apkSize;
  final String publishedAt;

  const UpdateInfo({
    required this.version,
    this.notes = '',
    this.apkUrl,
    this.apkSize = 0,
    this.publishedAt = '',
  });

  String get releasePage => UpdateService.releasePage;
}

/// 应用内检查更新（数据源：GitHub Releases 最新正式版）
///
/// 流程：检查（仅比版本号，无新版零打扰）→ 静默下载 APK 到临时目录 →
/// 交系统 PackageInstaller 安装。安装确认框浮在本应用之上，不离开软件；
/// 系统「允许来自此来源」未授权时引导去开一次（系统设置，仅首次）。
class UpdateService {
  UpdateService._();

  static const String apiLatest =
      'https://api.github.com/repos/SongLiKod/jianju/releases/latest';
  static const String releasePage =
      'https://github.com/SongLiKod/jianju/releases';

  /// 与原生层约定的安装通道（MainActivity：canInstall/installApk/…）
  static const MethodChannel _updater = MethodChannel('jianju/updater');

  /// 检查更新：有新版返回 [UpdateInfo]，否则（含网络/解析失败）返回 null
  static Future<UpdateInfo?> check() async {
    await _cleanupApks();
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
    ));
    try {
      final resp = await dio.get<String>(apiLatest, options: Options(
        headers: {
          'User-Agent': 'jianju-updater',
          'Accept': 'application/vnd.github+json',
        },
      ));
      final body = resp.data;
      if (body == null || body.isEmpty) return null;
      final info = await PackageInfo.fromPlatform();
      return parseRelease(body, info.version);
    } catch (e) {
      debugPrint('[UPD] 检查更新失败：$e');
      return null;
    } finally {
      dio.close(force: true);
    }
  }

  /// 解析 Release JSON（离线可测）：tag 无更新/格式非法返回 null
  static UpdateInfo? parseRelease(String json, String currentVersion) {
    try {
      final data = jsonDecode(json);
      if (data is! Map<String, dynamic>) return null;
      final tag = (data['tag_name'] as String? ?? '').trim();
      if (tag.isEmpty || !isNewer(tag, currentVersion)) return null;
      String? apkUrl;
      var apkSize = 0;
      for (final raw in (data['assets'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final name = '${raw['name'] ?? ''}'.toLowerCase();
        final mime = '${raw['content_type'] ?? ''}';
        if (name.endsWith('.apk') || mime.contains('package-archive')) {
          final url = (raw['browser_download_url'] as String? ?? '').trim();
          if (url.isEmpty) continue;
          apkUrl = url;
          apkSize = (raw['size'] as num?)?.toInt() ?? 0;
          break;
        }
      }
      return UpdateInfo(
        version: tag,
        notes: (data['body'] as String?) ?? '',
        apkUrl: apkUrl,
        apkSize: apkSize,
        publishedAt: (data['published_at'] as String?) ?? '',
      );
    } catch (e) {
      debugPrint('[UPD] 解析 Release 失败：$e');
      return null;
    }
  }

  /// 版本号比较：去掉前缀 v 与 `-beta` 类后缀后逐段数值比较
  ///（`2.1.0` > `2.0.0`、`2.0.10` > `2.0.9`、`v2.0.0` 不比 `2.0.0` 新）
  static bool isNewer(String remote, String current) {
    final a = _parts(remote);
    final b = _parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _parts(String v) => v
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split(RegExp(r'[^0-9]+'))
      .where((s) => s.isNotEmpty)
      .map(int.tryParse)
      .whereType<int>()
      .toList();

  /// 静默下载 APK 到临时目录；成功返回文件，失败返回 null
  ///（deleteOnError：截断/网络中断不留半截包；结尾校验 `PK` 魔数防错误页）
  static Future<File?> downloadApk(
    UpdateInfo info,
    void Function(int received, int total)? onProgress,
    {CancelToken? cancelToken}
  ) async {
    if (info.apkUrl == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/jianju_update_${info.version}.apk');
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    try {
      await dio.download(
        info.apkUrl!,
        file.path,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: onProgress,
        options: Options(headers: {'User-Agent': 'jianju-updater'}),
      );
      if (!await file.exists()) return null;
      final len = await file.length();
      if (len < 1024 * 1024) throw Exception('下载体积异常 ${len}B');
      final head = await file.openRead(0, 2).expand((b) => b).toList();
      if (head.length < 2 || head[0] != 0x50 || head[1] != 0x4B) {
        throw Exception('内容不是 APK（缺少 PK 头）');
      }
      debugPrint('[UPD] 下载完成 ${info.version} '
          '${(len / 1024 / 1024).toStringAsFixed(1)}MB');
      return file;
    } catch (e) {
      debugPrint('[UPD] 下载失败：$e');
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return null;
    } finally {
      dio.close(force: true);
    }
  }

  /// 系统是否已允许本应用安装 APK（首次为 false，需去设置开一次）
  static Future<bool> canInstall() async {
    try {
      return await _updater.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 打开系统「允许来自此来源」授权页（仅首次需要，用完自动回来继续）
  static Future<void> openInstallSettings() async {
    try {
      await _updater.invokeMethod('openInstallSettings');
    } on PlatformException catch (e) {
      debugPrint('[UPD] 打开安装授权页失败：$e');
    }
  }

  /// 交系统 PackageInstaller 安装（确认框浮在本应用上，不离开软件）。
  /// 返回 null = 已提交，否则为错误码（`blocked` = 未授权安装）
  static Future<String?> installApk(String path) async {
    try {
      await _updater.invokeMethod<String>('installApk', path);
      return null;
    } on PlatformException catch (e) {
      debugPrint('[UPD] 安装提交失败 code=${e.code} msg=${e.message}');
      if (e.code == 'blocked') return 'blocked';
      final msg = (e.message ?? '').trim();
      return msg.isEmpty ? e.code : '$e.code：$msg';
    }
  }

  /// 系统异步安装回执监听（status 0=成功，其余=失败；message 为系统原文）
  static void Function(int status, String message)? onInstallStatus;
  static bool _statusChannelReady = false;

  /// 注册回执监听（当前唯一使用方：更新弹窗，覆盖/清空都走这里）
  static void listenInstallStatus(
    void Function(int status, String message) handler,
  ) {
    onInstallStatus = handler;
    if (_statusChannelReady) return;
    _statusChannelReady = true;
    _updater.setMethodCallHandler((call) async {
      if (call.method != 'installStatus') return null;
      final args = call.arguments;
      if (args is Map) {
        onInstallStatus?.call(
          (args['status'] as num?)?.toInt() ?? -1,
          '${args['message'] ?? ''}',
        );
      }
      return null;
    });
  }

  static void cancelInstallStatusListener() => onInstallStatus = null;

  /// 把系统安装失败原文译成可读原因（未知原文原样返回，离线可测）
  static String humanizeInstallError(String message) {
    final m = message.trim();
    if (m.isEmpty) return '安装失败，请重试';
    if (m.contains('VERSION_DOWNGRADE')) {
      return '安装失败：新包版本号低于当前已安装版本，'
          '请发布更高版本号的安装包后再更新';
    }
    if (m.contains('UPDATE_INCOMPATIBLE') || m.contains('SIGNATURE')) {
      return '安装失败：新包与已安装应用签名不一致，需先卸载旧版再安装';
    }
    if (m.contains('INSUFFICIENT_STORAGE')) {
      return '安装失败：设备存储空间不足';
    }
    if (m.contains('CONFLICT')) {
      return '安装失败：与已安装应用冲突';
    }
    if (m.contains('INVALID_APK') || m.contains('PARSE')) {
      return '安装失败：安装包损坏，请重新下载';
    }
    if (m.contains('ABORTED')) {
      return '安装已取消';
    }
    return '安装失败：$m';
  }

  /// 清掉上次没用上的更新包（提交后系统已把内容拷走，临时包可删）
  static Future<void> _cleanupApks() async {
    try {
      final dir = await getTemporaryDirectory();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        if (entity.path.endsWith('.apk')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
