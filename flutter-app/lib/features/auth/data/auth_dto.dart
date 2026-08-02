import '../../../core/utils/formatters.dart';
import '../../../shared/domain/user_entity.dart';
import '../domain/auth_entity.dart';

/// 登录/注册响应 DTO
class AuthDto {
  const AuthDto({required this.user, required this.tokens});

  final UserDto user;
  final TokenDto tokens;

  factory AuthDto.fromJson(Map<String, dynamic> json) {
    return AuthDto(
      user: UserDto.fromJson(json['user'] as Map<String, dynamic>),
      tokens: TokenDto.fromJson(json['tokens'] as Map<String, dynamic>),
    );
  }

  AuthEntity toEntity() =>
      AuthEntity(user: user.toEntity(), tokens: tokens.toEntity());
}

/// 用户 DTO
class UserDto {
  const UserDto({
    required this.id,
    required this.userId,
    required this.nickname,
    this.avatar = '',
    this.bio = '',
    this.location = '',
    this.gender = 0,
    this.genderText = '',
    this.zodiacSign = '',
    this.mbti = '',
    this.education = '',
    this.major = '',
    this.interests = const [],
    this.followCount = 0,
    this.fansCount = 0,
    this.likeCount = 0,
    this.postCount = 0,
    this.verified = 0,
    this.isActive = 1,
    this.createdAt,
  });

  final int id;
  final String userId;
  final String nickname;
  final String avatar;
  final String bio;
  final String location;
  final int gender;
  final String genderText;
  final String zodiacSign;
  final String mbti;
  final String education;
  final String major;
  final List<String> interests;
  final int followCount;
  final int fansCount;
  final int likeCount;
  final int postCount;
  final int verified;
  final int isActive;
  final DateTime? createdAt;

  factory UserDto.fromJson(Map<String, dynamic> json) {
    return UserDto(
      id: parseInt(json['id']),
      userId: cleanString(json['user_id']),
      nickname: cleanString(json['nickname']),
      avatar: cleanString(json['avatar']),
      bio: cleanString(json['bio']),
      location: cleanString(json['location']),
      gender: parseInt(json['gender']),
      genderText: cleanString(json['gender']),
      zodiacSign: cleanString(json['zodiac_sign']),
      mbti: cleanString(json['mbti']),
      education: cleanString(json['education']),
      major: cleanString(json['major']),
      interests: _parseInterests(json['interests']),
      followCount: parseInt(json['follow_count']),
      fansCount: parseInt(json['fans_count']),
      likeCount: parseInt(json['like_count']),
      postCount: parseInt(json['post_count']),
      verified: parseInt(json['verified']),
      isActive: parseInt(json['is_active'], fallback: 1),
      createdAt: tryParseDateTime(json['created_at'] as String?),
    );
  }

  /// 解析 interests 字段
  static List<String> _parseInterests(Object? raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map((e) => cleanString(e))
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    final s = cleanString(raw);
    if (s.isEmpty) return const [];
    return s
        .split(',')
        .map((e) => e.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
  }

  UserEntity toEntity() => UserEntity(
    id: id,
    userId: userId,
    nickname: nickname,
    avatar: getFullImageUrl(avatar),
    bio: bio,
    location: location,
    gender: gender,
    genderText: genderText,
    zodiacSign: zodiacSign,
    mbti: mbti,
    education: education,
    major: major,
    interests: interests,
    followCount: followCount,
    fansCount: fansCount,
    likeCount: likeCount,
    postCount: postCount,
    verified: verified,
    isActive: isActive,
    createdAt: createdAt,
  );
}

/// 令牌 DTO
class TokenDto {
  const TokenDto({
    required this.accessToken,
    required this.refreshToken,
    this.expiresIn = 3600,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  factory TokenDto.fromJson(Map<String, dynamic> json) {
    return TokenDto(
      accessToken: (json['access_token'] ?? '').toString(),
      refreshToken: (json['refresh_token'] ?? '').toString(),
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 3600,
    );
  }

  TokenEntity toEntity() => TokenEntity(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresIn: expiresIn,
  );
}
