import '../constants/app_constants.dart';
import 'storage_service.dart';

/// 用户登录 Token 管理
///
/// 本项目无登录页（需求未要求），Token 仅做本地保存：
/// 若本机存在有效 Token 则随请求附带，退出登录仅清除本地 Token。
class TokenService {
  TokenService._();

  static String get token =>
      StorageService.getString(AppConstants.keyToken);

  static Future<void> save(String value) =>
      StorageService.setString(AppConstants.keyToken, value);

  static bool get hasToken => token.isNotEmpty;

  /// 退出登录：清除本地 token
  static Future<void> logout() => StorageService.remove(AppConstants.keyToken);
}
