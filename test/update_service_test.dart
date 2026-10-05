import 'package:flutter_test/flutter_test.dart';
import 'package:jianju/core/services/update_service.dart';

/// 应用内检查更新：版本号比较与 GitHub Release 解析（离线）
void main() {
  group('版本号比较', () {
    test('大版本新于旧版本', () {
      expect(UpdateService.isNewer('3.0.0', '2.0.0'), isTrue);
      expect(UpdateService.isNewer('v2.1.0', '2.0.0'), isTrue);
      expect(UpdateService.isNewer('2.10.0', '2.9.9'), isTrue);
      expect(UpdateService.isNewer('2.0.10', '2.0.9'), isTrue);
    });

    test('相同与更旧版本不算新', () {
      expect(UpdateService.isNewer('2.0.0', '2.0.0'), isFalse);
      expect(UpdateService.isNewer('v2.0.0', '2.0.0'), isFalse);
      expect(UpdateService.isNewer('1.0.9', '2.0.0'), isFalse);
      expect(UpdateService.isNewer('2.0.0', '2.0.1'), isFalse);
    });

    test('预发布后缀按数字段比较', () {
      expect(UpdateService.isNewer('v2.0.0-beta', '2.0.0'), isFalse);
      expect(UpdateService.isNewer('v2.1.0-beta', '2.0.0'), isTrue);
      expect(UpdateService.isNewer('v2.0.1', '2.0.0-beta'), isTrue);
    });
  });

  group('Release 解析', () {
    const fixture = '''
{
  "tag_name": "v2.1.0",
  "name": "v2.1.0",
  "published_at": "2026-10-06T09:00:00Z",
  "body": "修复播放问题",
  "assets": [
    {
      "name": "Jianju-2.1.0-windows.zip",
      "content_type": "application/zip",
      "size": 34417927,
      "browser_download_url": "https://github.com/x/jianju/releases/download/v2.1.0/Jianju-2.1.0-windows.zip"
    },
    {
      "name": "Jianju-2.1.0.apk",
      "content_type": "application/vnd.android.package-archive",
      "size": 96906927,
      "browser_download_url": "https://github.com/x/jianju/releases/download/v2.1.0/Jianju-2.1.0.apk"
    }
  ]
}''';

    test('有新版时取 APK 资产与更新说明', () {
      final info = UpdateService.parseRelease(fixture, '2.0.0');
      expect(info, isNotNull);
      expect(info!.version, 'v2.1.0');
      expect(info.notes, '修复播放问题');
      expect(info.apkUrl, contains('Jianju-2.1.0.apk'));
      expect(info.apkSize, 96906927);
      expect(info.releasePage, contains('github.com'));
    });

    test('已是最新时返回 null', () {
      expect(UpdateService.parseRelease(fixture, '2.1.0'), isNull);
      expect(UpdateService.parseRelease(fixture, '3.0.0'), isNull);
    });

    test('非法 JSON / 无 tag_name 返回 null', () {
      expect(UpdateService.parseRelease('not json', '1.0.0'), isNull);
      expect(UpdateService.parseRelease('[]', '1.0.0'), isNull);
      expect(UpdateService.parseRelease('{"assets":[]}', '1.0.0'), isNull);
    });

    test('没有 APK 资产也要给出版本信息（桌面端可走发布页）', () {
      const noApk = '''
{
  "tag_name": "v3.0.0",
  "body": "note",
  "assets": [{"name": "Jianju-3.0.0-windows.zip",
    "browser_download_url": "https://github.com/x/j.zip"}]
}''';
      final info = UpdateService.parseRelease(noApk, '2.0.0');
      expect(info, isNotNull);
      expect(info!.apkUrl, isNull);
    });
  });

  group('安装失败原因中文化', () {
    test('版本降级给出可操作说明', () {
      final s = UpdateService.humanizeInstallError(
        'INSTALL_FAILED_VERSION_DOWNGRADE: Downgrade detected',
      );
      expect(s, contains('版本号'));
      expect(s, contains('更高版本号'));
    });

    test('签名不一致提示先卸载', () {
      final s = UpdateService.humanizeInstallError(
        'INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match',
      );
      expect(s, contains('签名'));
      expect(s, contains('卸载'));
    });

    test('存储不足 / 包损坏 / 已取消', () {
      expect(UpdateService.humanizeInstallError('INSTALL_FAILED_INSUFFICIENT_STORAGE'),
          contains('存储空间'));
      expect(UpdateService.humanizeInstallError('INSTALL_FAILED_INVALID_APK'),
          contains('损坏'));
      expect(UpdateService.humanizeInstallError('INSTALL_FAILED_ABORTED'),
          contains('取消'));
    });

    test('空消息与未知原因都给出可读文案', () {
      expect(UpdateService.humanizeInstallError('  '), '安装失败，请重试');
      expect(
        UpdateService.humanizeInstallError('something weird'),
        '安装失败：something weird',
      );
    });

    test('拿不到系统安装服务（createSession NPE）提示手动安装', () {
      final s = UpdateService.humanizeInstallError(
        "install：Attempt to invoke virtual method "
        "'int android.content.pm.PackageInstaller.createSession("
        "android.content.pm.PackageInstaller\$SessionParams)' "
        'on a null object reference',
      );
      expect(s, contains('手动安装'));
      expect(s, isNot(contains('null object')));
    });
  });
}
