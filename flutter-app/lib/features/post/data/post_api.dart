import 'package:dio/dio.dart';

import '../../../core/constants/api_paths.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/paged_data.dart';
import 'post_dto.dart';

class PostApi {
  const PostApi(this._client);

  final DioClient _client;

  Future<PagedData<PostDto>> list({
    String? category,
    int page = 1,
    int limit = 20,
    int? userId,
    int? isDraft,
  }) {
    return _client.getPaged(
      ApiPaths.posts,
      query: {
        if (category != null && category.isNotEmpty) 'category': category,
        'page': page,
        'limit': limit,
        if (userId != null) 'user_id': userId,
        if (isDraft != null) 'is_draft': isDraft,
      },
      listKey: 'posts',
      decode: PostDto.fromJson,
    );
  }

  Future<List<CategoryDto>> categories() async {
    final list = await _client.get(
      ApiPaths.categories,
      decode: (d) => (d as List<dynamic>)
          .map((e) => CategoryDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
    return list;
  }

  Future<PostDto> detail(int id) {
    return _client.get(
      ApiPaths.post(id),
      decode: (d) => PostDto.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<PagedData<CommentDto>> comments(
    int postId, {
    int page = 1,
    int limit = 20,
  }) {
    return _client.getPaged(
      ApiPaths.postComments(postId),
      query: {'page': page, 'limit': limit},
      listKey: 'comments',
      decode: CommentDto.fromJson,
    );
  }

  Future<PagedData<CommentDto>> replies(
    int commentId, {
    int page = 1,
    int limit = 10,
  }) {
    return _client.getPaged(
      ApiPaths.commentReplies(commentId),
      query: {'page': page, 'limit': limit},
      listKey: 'comments',
      decode: CommentDto.fromJson,
    );
  }

  Future<CommentDto> createComment(
    int postId, {
    required String content,
    int? parentId,
  }) {
    return _client.post(
      ApiPaths.comments,
      data: {
        'post_id': postId,
        'content': content,
        if (parentId != null) 'parent_id': parentId,
      },
      decode: (d) => CommentDto.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<void> deleteComment(int commentId) =>
      _client.deleteVoid(ApiPaths.comment(commentId));

  Future<bool> like({required int targetType, required int targetId}) async {
    final res = await _client.post(
      ApiPaths.likes,
      data: {'target_type': targetType, 'target_id': targetId},
      decode: (d) => LikeResultDto.fromJson(d as Map<String, dynamic>),
    );
    return res.liked;
  }

  Future<void> unlike({required int targetType, required int targetId}) {
    return _client.deleteVoid(
      ApiPaths.likes,
      data: {'target_type': targetType, 'target_id': targetId},
    );
  }

  Future<bool> collect(int postId) async {
    final res = await _client.post(
      ApiPaths.postCollect(postId),
      decode: (d) => CollectResultDto.fromJson(d as Map<String, dynamic>),
    );
    return res.collected;
  }

  Future<void> uncollect(int postId) =>
      _client.deleteVoid(ApiPaths.postCollect(postId));

  Future<PagedData<PostDto>> search({
    required String keyword,
    int page = 1,
    int limit = 20,
    int? categoryId,
  }) {
    return _client.getPaged(
      ApiPaths.postsSearch,
      query: {
        'keyword': keyword,
        'page': page,
        'limit': limit,
        if (categoryId != null) 'category_id': categoryId,
      },
      listKey: 'posts',
      decode: PostDto.fromJson,
    );
  }

  /// 删除笔记：`DELETE /api/posts/:id`。
  Future<void> deletePost(int id) => _client.deleteVoid(ApiPaths.post(id));

  /// 创建笔记：`POST /api/posts`。
  Future<PostDto> create(Map<String, dynamic> payload) {
    return _client.post(
      ApiPaths.posts,
      data: payload,
      decode: (d) => PostDto.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<PostDto> update(int id, Map<String, dynamic> payload) {
    return _client.put(
      ApiPaths.post(id),
      data: payload,
      decode: (d) => PostDto.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<void> view(int id) async {
    try {
      await _client.postVoid(ApiPaths.postView(id));
    } on DioException {
    }
  }

  Future<List<String>> hotTags({int limit = 10}) async {
    final list = await _client.get(
      ApiPaths.tagsHot,
      query: {'limit': limit},
      decode: (d) => (d as List<dynamic>)
          .map((e) => ((e as Map<String, dynamic>)['name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList(),
    );
    return list;
  }
}
