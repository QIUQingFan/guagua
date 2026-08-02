import 'dart:convert';

import '../../../core/utils/formatters.dart';
import '../../../shared/domain/user_entity.dart';

/// 用户详情 DTO：字段与后端 snake_case 一致。
class UserDetailDto {
  const UserDetailDto({
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

  factory UserDetailDto.fromJson(Map<String, dynamic> json) {
    return UserDetailDto(
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

  /// 解析 interests 字段：后端可能返回 List / JSON 字符串 / 逗号分隔字符串。
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
    if (s.startsWith('[')) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is List) {
          return decoded
              .map((e) => cleanString(e))
              .where((t) => t.isNotEmpty)
              .toList(growable: false);
        }
      } catch (_) {
      }
    }
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

/// 用户统计 DTO：`{posts_count, likes_count, ...}`。
class UserStatsDto {
  const UserStatsDto({
    this.postsCount = 0,
    this.likesCount = 0,
    this.collectionsCount = 0,
    this.commentsCount = 0,
    this.followersCount = 0,
    this.followingCount = 0,
    this.viewsCount = 0,
  });

  final int postsCount;
  final int likesCount;
  final int collectionsCount;
  final int commentsCount;
  final int followersCount;
  final int followingCount;
  final int viewsCount;

  factory UserStatsDto.fromJson(Map<String, dynamic> json) {
    return UserStatsDto(
      postsCount: (json['posts_count'] as num?)?.toInt() ?? 0,
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      collectionsCount: (json['collections_count'] as num?)?.toInt() ?? 0,
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
      followersCount: (json['followers_count'] as num?)?.toInt() ?? 0,
      followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
      viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class UserStatsEntity {
  const UserStatsEntity({
    this.postsCount = 0,
    this.likesCount = 0,
    this.collectionsCount = 0,
    this.followersCount = 0,
    this.followingCount = 0,
  });

  final int postsCount;
  final int likesCount;
  final int collectionsCount;
  final int followersCount;
  final int followingCount;
}
