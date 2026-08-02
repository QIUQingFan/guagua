import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_data.dart';
import '../../../shared/domain/post_entity.dart';
import '../../../shared/domain/user_entity.dart';
import '../../../shared/providers/core_providers.dart';
import '../../auth/application/auth_controller.dart';
import 'user_api.dart';
import 'user_dto.dart';

class UserRepository {
  const UserRepository(this._api);
  final UserApi _api;

  /// [userId] 为瓜呱号字符串（后端 `users.user_id`）。
  Future<UserEntity> detail(String userId) async =>
      (await _api.detail(userId)).toEntity();

  Future<UserStatsEntity> stats(String userId) async {
    final dto = await _api.stats(userId);
    return UserStatsEntity(
      postsCount: dto.postsCount,
      likesCount: dto.likesCount,
      collectionsCount: dto.collectionsCount,
      followersCount: dto.followersCount,
      followingCount: dto.followingCount,
    );
  }

  Future<UserEntity> update(
    String userId, {
    String? nickname,
    String? avatar,
    String? bio,
    String? location,
    String? gender,
    String? zodiacSign,
    String? mbti,
    String? education,
    String? major,
    List<String>? interests,
  }) async {
    return (await _api.update(
      userId,
      nickname: nickname,
      avatar: avatar,
      bio: bio,
      location: location,
      gender: gender,
      zodiacSign: zodiacSign,
      mbti: mbti,
      education: education,
      major: major,
      interests: interests,
    )).toEntity();
  }

  Future<void> follow(String userId) => _api.follow(userId);
  Future<void> unfollow(String userId) => _api.unfollow(userId);

  Future<PagedData<UserEntity>> search({
    required String keyword,
    int page = 1,
    int limit = 20,
  }) async {
    final paged = await _api.search(keyword: keyword, page: page, limit: limit);
    return PagedData<UserEntity>(
      list: paged.list.map((e) => e.toEntity()).toList(),
      total: paged.total,
      page: paged.page,
      limit: paged.limit,
      hasMore: paged.hasMore,
    );
  }

  /// 用户发布的笔记。[userId] 为瓜呱号字符串。
  Future<PagedData<PostEntity>> posts(
    String userId, {
    int page = 1,
    int limit = 20,
  }) async {
    final paged = await _api.posts(userId, page: page, limit: limit);
    return PagedData<PostEntity>(
      list: paged.list.map((e) => e.toEntity()).toList(),
      total: paged.total,
      page: paged.page,
      limit: paged.limit,
      hasMore: paged.hasMore,
    );
  }

  /// 用户收藏的笔记。[userId] 为瓜呱号字符串。
  Future<PagedData<PostEntity>> collections(
    String userId, {
    int page = 1,
    int limit = 20,
  }) async {
    final paged = await _api.collections(userId, page: page, limit: limit);
    return PagedData<PostEntity>(
      list: paged.list.map((e) => e.toEntity()).toList(),
      total: paged.total,
      page: paged.page,
      limit: paged.limit,
      hasMore: paged.hasMore,
    );
  }

  Future<PagedData<PostEntity>> likes(
    String userId, {
    int page = 1,
    int limit = 20,
  }) async {
    final paged = await _api.likes(userId, page: page, limit: limit);
    return PagedData<PostEntity>(
      list: paged.list.map((e) => e.toEntity()).toList(),
      total: paged.total,
      page: paged.page,
      limit: paged.limit,
      hasMore: paged.hasMore,
    );
  }
}

final userApiProvider = Provider<UserApi>(
  (ref) => UserApi(ref.watch(dioClientProvider)),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(ref.watch(userApiProvider)),
);

/// 当前登录用户 ID（便捷派生）。
final currentUserIdProvider = Provider<int?>((ref) {
  return ref.watch(currentUserProvider)?.id;
});
