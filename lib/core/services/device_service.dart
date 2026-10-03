import 'dart:math';

import '../constants/app_constants.dart';
import 'storage_service.dart';

/// 设备信息服务（风控节流策略的一部分）
///
/// 首次启动生成一套随机设备参数并永久本地保存；
/// 支持在设置页一键重置设备 ID（降低账号/设备封禁概率）。
class DeviceService {
  DeviceService._();

  static String _installId = '';
  static String _deviceId = '';
  static String _cdid = '';

  static Future<void> init() async {
    _installId = StorageService.getString(AppConstants.keyInstallId);
    _deviceId = StorageService.getString(AppConstants.keyDeviceId);
    _cdid = StorageService.getString(AppConstants.keyCdid);
    if (_installId.isEmpty || _deviceId.isEmpty || _cdid.isEmpty) {
      await reset();
    }
  }

  /// 重新生成一套随机设备信息
  static Future<void> reset() async {
    final rng = Random();
    _installId = _genLongId(rng);
    _deviceId = _genLongId(rng);
    _cdid = _genUuid(rng);
    await StorageService.setString(AppConstants.keyInstallId, _installId);
    await StorageService.setString(AppConstants.keyDeviceId, _deviceId);
    await StorageService.setString(AppConstants.keyCdid, _cdid);
  }

  /// 19 位数字 ID（对齐官方安装 ID 格式）
  static String _genLongId(Random rng) {
    final sb = StringBuffer();
    sb.write('1');
    for (var i = 0; i < 18; i++) {
      sb.write(rng.nextInt(10));
    }
    return sb.toString();
  }

  static String _genUuid(Random rng) {
    const hex = '0123456789abcdef';
    final sb = StringBuffer();
    for (var i = 0; i < 36; i++) {
      if (i == 8 || i == 13 || i == 18 || i == 23) {
        sb.write('-');
      } else {
        sb.write(hex[rng.nextInt(16)]);
      }
    }
    return sb.toString();
  }

  static String get installId => _installId;
}
