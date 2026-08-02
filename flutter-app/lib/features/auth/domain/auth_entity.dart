import '../../../shared/domain/user_entity.dart';

/// 令牌实体
class TokenEntity {
  const TokenEntity({
    required this.accessToken,
    required this.refreshToken,
    this.expiresIn = 3600,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
}

/// 认证实体
class AuthEntity {
  const AuthEntity({required this.user, required this.tokens});

  final UserEntity user;
  final TokenEntity tokens;

  AuthEntity copyWith({UserEntity? user, TokenEntity? tokens}) {
    return AuthEntity(user: user ?? this.user, tokens: tokens ?? this.tokens);
  }
}
