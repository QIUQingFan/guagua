import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_data.dart';
import '../../../shared/domain/comment_entity.dart';
import '../../../shared/domain/post_entity.dart';
import '../../../shared/domain/user_entity.dart';
import '../../../shared/providers/core_providers.dart';
import 'post_api.dart';

class PostRepository {
  const PostRepository(this._api);

  final PostApi _api;

  Future<List<CategoryEntity>> categories() async {
    final list = await _api.categories();
    return list.map((e) => e.toEntity()).toList();
  }

  Future<PagedData<PostEntity>> list({
    String? category,
    int page = 1,
    int limit = 20,
    int? userId,
    int? isDraft,
  }) async {
    final paged = await _api.list(
      category: category,
      page: page,
      limit: limit,
      userId: userId,
      isDraft: isDraft,
    );
    return _mapPaged(paged, (e) => e.toEntity());
  }

  Future<PostDetailEntity> detail(int id) async {
    final dto = await _api.detail(id);
    final post = dto.toEntity();
    final author =
        dto.user?.toEntity() ??
        UserEntity(
          id: dto.userId,
          userId: dto.userDisplayId.isNotEmpty
              ? dto.userDisplayId
              : dto.userId.toString(),
          nickname: dto.nickname,
          avatar: dto.userAvatar,
          verified: dto.verified,
        );
    return PostDetailEntity(post: post, author: author);
  }

  Future<PagedData<CommentEntity>> comments(
    int postId, {
    int page = 1,
    int limit = 20,
  }) async {
    final paged = await _api.comments(postId, page: page, limit: limit);
    return _mapPaged(paged, (e) => e.toEntity());
  }

  Future<PagedData<CommentEntity>> replies(
    int commentId, {
    int page = 1,
    int limit = 10,
  }) async {
    final paged = await _api.replies(commentId, page: page, limit: limit);
    return _mapPaged(paged, (e) => e.toEntity());
  }

  Future<CommentEntity> createComment(
    int postId, {
    required String content,
    int? parentId,
  }) async {
    final dto = await _api.createComment(
      postId,
      content: content,
      parentId: parentId,
    );
    return dto.toEntity();
  }

  Future<void> deleteComment(int commentId) => _api.deleteComment(commentId);

  Future<bool> likePost(int postId) =>
      _api.like(targetType: 1, targetId: postId);

  Future<void> unlikePost(int postId) =>
      _api.unlike(targetType: 1, targetId: postId);

  Future<bool> likeComment(int commentId) =>
      _api.like(targetType: 2, targetId: commentId);

  Future<void> unlikeComment(int commentId) =>
      _api.unlike(targetType: 2, targetId: commentId);

  Future<bool> collect(int postId) => _api.collect(postId);

  Future<void> uncollect(int postId) => _api.uncollect(postId);

  Future<PagedData<PostEntity>> search({
    required String keyword,
    int page = 1,
    int limit = 20,
  }) async {
    final paged = await _api.search(keyword: keyword, page: page, limit: limit);
    return _mapPaged(paged, (e) => e.toEntity());
  }

  Future<void> deletePost(int id) => _api.deletePost(id);

  Future<void> view(int id) => _api.view(id);

  Future<List<String>> hotTags({int limit = 10}) => _api.hotTags(limit: limit);

  Future<List<PostEntity>> related(int postId, {int limit = 6}) async {
    try {
      final detail = await _api.detail(postId);
      final category = detail.categoryId?.toString();
      if (category != null && category.isNotEmpty) {
        final paged = await _api.list(
          category: category,
          page: 1,
          limit: limit + 1,
        );
        return paged.list
            .where((p) => p.id != postId)
            .take(limit)
            .map((e) => e.toEntity())
            .toList();
      }
    } catch (_) {
    }
    try {
      final tags = await _api.hotTags(limit: 1);
      if (tags.isNotEmpty) {
        final paged = await _api.search(
          keyword: tags.first,
          page: 1,
          limit: limit + 1,
        );
        return paged.list
            .where((p) => p.id != postId)
            .take(limit)
            .map((e) => e.toEntity())
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}

final postApiProvider = Provider<PostApi>(
  (ref) => PostApi(ref.watch(dioClientProvider)),
);

final postRepositoryProvider = Provider<PostRepository>(
  (ref) => PostRepository(ref.watch(postApiProvider)),
);

PagedData<T> _mapPaged<S, T>(PagedData<S> source, T Function(S) converter) {
  return PagedData<T>(
    list: source.list.map(converter).toList(),
    total: source.total,
    page: source.page,
    limit: source.limit,
    hasMore: source.hasMore,
  );
}
