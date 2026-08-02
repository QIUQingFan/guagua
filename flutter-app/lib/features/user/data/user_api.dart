import '../../../core/constants/api_paths.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/paged_data.dart';
import '../../post/data/post_dto.dart';
import 'user_dto.dart';

/// 用户远程数据源。
///
/// 注意：后端 `/api/users/:id` 系列接口的 `:id` 参数统一为**瓜呱号字符串**
/// （`users.user_id`，如 `guagua_001`），**不是**自增数字主键 `id`。
/// 这与 web 端约定一致。本层方法参数命名为 [userId] 以明确语义。
class UserApi {
  const UserApi(this._client);

  final DioClient _client;

  /// 用户详情：`GET /api/users/:userId`。
  Future<UserDetailDto> detail(String userId) {
    return _client.get(
      ApiPaths.user(userId),
      decode: (d) => UserDetailDto.fromJson(d as Map<String, dynamic>),
    );
  }

  /// 用户发布的笔记：`GET /api/users/:userId/posts`。
  Future<PagedData<PostDto>> posts(
    String userId, {
    int page = 1,
    int limit = 20,
  }) {
    return _client.getPaged(
      ApiPaths.userPosts(userId),
      query: {'page': page, 'limit': limit},
      listKey: 'posts',
      decode: PostDto.fromJson,
    );
  }

  /// 用户收藏的笔记：`GET /api/users/:userId/collections`。
  Future<PagedData<PostDto>> collections(
    String userId, {
    int page = 1,
    int limit = 20,
  }) {
    return _client.getPaged(
      ApiPaths.userCollections(userId),
      query: {'page': page, 'limit': limit},
      listKey: 'collections',
      decode: PostDto.fromJson,
    );
  }

  /// 用户点赞的笔记：`GET /api/users/:userId/likes`
  Future<PagedData<PostDto>> likes(
    String userId, {
    int page = 1,
    int limit = 20,
  }) {
    return _client.getPaged(
      ApiPaths.userLikes(userId),
      query: {'page': page, 'limit': limit},
      listKey: 'likes',
      decode: PostDto.fromJson,
    );
  }

  /// 更新用户：`PUT /api/users/:userId`。
  Future<UserDetailDto> update(
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
  }) {
    return _client.put(
      ApiPaths.user(userId),
      data: {
        if (nickname != null) 'nickname': nickname,
        if (avatar != null) 'avatar': avatar,
        if (bio != null) 'bio': bio,
        if (location != null) 'location': location,
        if (gender != null) 'gender': gender,
        if (zodiacSign != null) 'zodiac_sign': zodiacSign,
        if (mbti != null) 'mbti': mbti,
        if (education != null) 'education': education,
        if (major != null) 'major': major,
        if (interests != null) 'interests': interests,
      },
      decode: (d) => UserDetailDto.fromJson(d as Map<String, dynamic>),
    );
  }

  /// 用户统计：`GET /api/users/:userId/stats`。
  Future<UserStatsDto> stats(String userId) {
    return _client.get(
      ApiPaths.userStats(userId),
      decode: (d) => UserStatsDto.fromJson(d as Map<String, dynamic>),
    );
  }

  /// 关注：`POST /api/users/:userId/follow`。
  Future<void> follow(String userId) =>
      _client.postVoid(ApiPaths.userFollow(userId));

  /// 取关：`DELETE /api/users/:userId/follow`。
  Future<void> unfollow(String userId) =>
      _client.deleteVoid(ApiPaths.userFollow(userId));

  /// 搜索用户：`GET /api/users/search?keyword=`。
  Future<PagedData<UserDetailDto>> search({
    required String keyword,
    int page = 1,
    int limit = 20,
  }) {
    return _client.getPaged(
      ApiPaths.usersSearch,
      query: {'keyword': keyword, 'page': page, 'limit': limit},
      listKey: 'users',
      decode: UserDetailDto.fromJson,
    );
  }
}
