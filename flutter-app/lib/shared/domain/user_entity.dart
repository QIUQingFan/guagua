/// 用户领域实体（跨模块共享）。
///
/// 字段对应后端 `user` 对象（snake_case）经 camelCase 归一化。
class UserEntity {
  const UserEntity({
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

  /// 用户自增主键（后端 `id`）。
  final int id;

  /// 瓜呱号（后端 `user_id`，字符串）。
  final String userId;

  final String nickname;
  final String avatar;
  final String bio;
  final String location;

  /// 0 未知 / 1 男 / 2 女（兼容旧逻辑，后端实际存储为字符串）。
  final int gender;

  /// 性别文本（后端 `gender` 为 varchar，如 '男' / '女'）。
  final String genderText;

  /// 星座（后端 `zodiac_sign`）。
  final String zodiacSign;

  /// MBTI 人格类型（后端 `mbti`）。
  final String mbti;

  /// 学历（后端 `education`）。
  final String education;

  /// 专业（后端 `major`）。
  final String major;

  /// 兴趣爱好（后端 `interests` JSON 数组）。
  final List<String> interests;

  final int followCount;
  final int fansCount;
  final int likeCount;
  final int postCount;

  /// 0 未认证 / 1 已认证。
  final int verified;
  final int isActive;
  final DateTime? createdAt;

  bool get isVerified => verified == 1;

  UserEntity copyWith({
    int? id,
    String? userId,
    String? nickname,
    String? avatar,
    String? bio,
    String? location,
    int? gender,
    String? genderText,
    String? zodiacSign,
    String? mbti,
    String? education,
    String? major,
    List<String>? interests,
    int? followCount,
    int? fansCount,
    int? likeCount,
    int? postCount,
    int? verified,
    int? isActive,
    DateTime? createdAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      bio: bio ?? this.bio,
      location: location ?? this.location,
      gender: gender ?? this.gender,
      genderText: genderText ?? this.genderText,
      zodiacSign: zodiacSign ?? this.zodiacSign,
      mbti: mbti ?? this.mbti,
      education: education ?? this.education,
      major: major ?? this.major,
      interests: interests ?? this.interests,
      followCount: followCount ?? this.followCount,
      fansCount: fansCount ?? this.fansCount,
      likeCount: likeCount ?? this.likeCount,
      postCount: postCount ?? this.postCount,
      verified: verified ?? this.verified,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
