import '../../../core/constants/api_paths.dart';
import '../../../core/network/dio_client.dart';
import 'auth_dto.dart';

/// 验证码响应
class CaptchaDto {
  const CaptchaDto({required this.captchaId, required this.captchaSvg});

  final String captchaId;
  final String captchaSvg;
}

/// 认证远程数据源
class AuthApi {
  const AuthApi(this._client);

  final DioClient _client;

  /// 获取图形验证码
  Future<CaptchaDto> captcha() {
    return _client.get(
      ApiPaths.authCaptcha,
      decode: (d) {
        final m = d as Map<String, dynamic>;
        return CaptchaDto(
          captchaId: (m['captchaId'] ?? '').toString(),
          captchaSvg: (m['captchaSvg'] ?? '').toString(),
        );
      },
    );
  }

  /// 注册
  Future<AuthDto> register({
    required String userId,
    required String nickname,
    required String password,
    required String captchaId,
    required String captchaText,
    String? avatar,
    String? bio,
    String? location,
  }) {
    return _client.post(
      ApiPaths.authRegister,
      data: {
        'user_id': userId,
        'nickname': nickname,
        'password': password,
        'captchaId': captchaId,
        'captchaText': captchaText,
        if (avatar != null) 'avatar': avatar,
        if (bio != null) 'bio': bio,
        if (location != null) 'location': location,
      },
      decode: (d) => AuthDto.fromJson(d as Map<String, dynamic>),
    );
  }

  /// 登录
  Future<AuthDto> login({required String userId, required String password}) {
    return _client.post(
      ApiPaths.authLogin,
      data: {'user_id': userId, 'password': password},
      decode: (d) => AuthDto.fromJson(d as Map<String, dynamic>),
    );
  }

  /// 刷新令牌
  Future<TokenDto> refresh(String refreshToken) {
    return _client.post(
      ApiPaths.authRefresh,
      data: {'refresh_token': refreshToken},
      decode: (d) => TokenDto.fromJson(d as Map<String, dynamic>),
    );
  }

  /// 退出登录
  Future<void> logout() => _client.postVoid(ApiPaths.authLogout);

  /// 当前用户
  Future<UserDto> me() {
    return _client.get(
      ApiPaths.authMe,
      decode: (d) => UserDto.fromJson(d as Map<String, dynamic>),
    );
  }
}
