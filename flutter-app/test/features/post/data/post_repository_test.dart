import 'package:flutter_test/flutter_test.dart';
import 'package:guagua/core/network/paged_data.dart';
import 'package:guagua/features/post/data/post_api.dart';
import 'package:guagua/features/post/data/post_dto.dart';
import 'package:guagua/features/post/data/post_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockPostApi extends Mock implements PostApi {}

final _postDto = PostDto.fromJson({
  'id': 100,
  'user_id': 42,
  'title': '夏日西瓜图鉴',
  'content': '夏天到了，一起来吃瓜~',
  'type': 1,
  'category_id': 7,
  'images': ['https://cdn.example.com/1.jpg', 'https://cdn.example.com/2.jpg'],
  'tags': ['西瓜', '夏日'],
  'nickname': '瓜呱',
  'user_avatar': 'https://cdn.example.com/a.png',
  'verified': 1,
  'view_count': 1000,
  'like_count': 99,
  'comment_count': 12,
  'collect_count': 5,
  'isLiked': true,
  'isCollected': false,
  'created_at': '2026-07-26T08:00:00.000Z',
});

final _postDtoWithUser = PostDto.fromJson({
  ..._postDtoJsonBase,
  'user': {
    'id': 42,
    'user_id': 'guagua_001',
    'nickname': '瓜呱',
    'avatar': 'https://cdn.example.com/a.png',
    'bio': '热爱生活',
    'location': '上海',
    'verified': 1,
    'is_active': 1,
  },
});

const _postDtoJsonBase = <String, dynamic>{
  'id': 100,
  'user_id': 42,
  'title': '夏日西瓜图鉴',
  'content': '夏天到了，一起来吃瓜~',
  'type': 1,
  'category_id': 7,
  'images': ['https://cdn.example.com/1.jpg', 'https://cdn.example.com/2.jpg'],
  'tags': ['西瓜', '夏日'],
  'nickname': '瓜呱',
  'user_avatar': 'https://cdn.example.com/a.png',
  'verified': 1,
  'view_count': 1000,
  'like_count': 99,
  'comment_count': 12,
  'collect_count': 5,
  'isLiked': true,
  'isCollected': false,
  'created_at': '2026-07-26T08:00:00.000Z',
};

final _categoryDto1 = CategoryDto(id: 1, name: '推荐', title: '为你推荐', postCount: 100);
final _categoryDto2 = CategoryDto(id: 2, name: '美食', title: '好吃好喝', postCount: 50);

final _commentDto = CommentDto.fromJson({
  'id': 200,
  'content': '看起来好好吃',
  'user_id': 50,
  'nickname': '吃货',
  'user_avatar': 'https://cdn.example.com/b.png',
  'verified': 0,
  'post_id': 100,
  'parent_id': null,
  'reply_count': 3,
  'liked': false,
  'created_at': '2026-07-26T09:00:00.000Z',
});

PagedData<T> _paged<T>(List<T> list, {int total = 0, int page = 1, int limit = 20, bool hasMore = false}) {
  return PagedData<T>(list: list, total: total, page: page, limit: limit, hasMore: hasMore);
}

void main() {
  late _MockPostApi api;
  late PostRepository repo;

  setUp(() {
    api = _MockPostApi();
    repo = PostRepository(api);
  });

  group('PostRepository.categories', () {
    test('将 CategoryDto 列表转为 CategoryEntity 列表', () async {
      when(() => api.categories()).thenAnswer((_) async => [_categoryDto1, _categoryDto2]);

      final list = await repo.categories();

      expect(list.length, 2);
      expect(list[0].id, 1);
      expect(list[0].name, '推荐');
      expect(list[0].title, '为你推荐');
      expect(list[0].postCount, 100);
      expect(list[1].id, 2);
      expect(list[1].name, '美食');
    });

    test('空列表保持空', () async {
      when(() => api.categories()).thenAnswer((_) async => []);

      final list = await repo.categories();

      expect(list, isEmpty);
    });
  });

  group('PostRepository.list', () {
    test('将 PagedData<PostDto> 转为 PagedData<PostEntity>，保留分页元信息', () async {
      when(
        () => api.list(
          category: 'recommend',
          page: 1,
          limit: 20,
          userId: null,
          isDraft: null,
        ),
      ).thenAnswer((_) async => _paged([_postDto], total: 100, page: 1, hasMore: true));

      final paged = await repo.list(category: 'recommend', page: 1);

      expect(paged.list.length, 1);
      expect(paged.total, 100);
      expect(paged.page, 1);
      expect(paged.hasMore, isTrue);

      final post = paged.list.first;
      expect(post.id, 100);
      expect(post.authorId, 42);
      expect(post.authorNickname, '瓜呱');
      expect(post.authorVerified, isTrue);
      expect(post.title, '夏日西瓜图鉴');
      expect(post.content, '夏天到了，一起来吃瓜~');
      expect(post.isVideo, isFalse);
      expect(post.imageUrls.length, 2);
      expect(post.tags, ['西瓜', '夏日']);
      expect(post.likeCount, 99);
      expect(post.liked, isTrue);
      expect(post.collected, isFalse);
      expect(post.categoryId, 7);
      expect(post.createdAt, isNotNull);
    });

    test('透传 userId / isDraft 参数', () async {
      when(
        () => api.list(
          category: any(named: 'category'),
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          userId: 42,
          isDraft: 1,
        ),
      ).thenAnswer((_) async => _paged<PostDto>([]));

      await repo.list(userId: 42, isDraft: 1);

      verify(
        () => api.list(
          category: null,
          page: 1,
          limit: 20,
          userId: 42,
          isDraft: 1,
        ),
      ).called(1);
    });

    test('视频笔记：isVideo 正确', () async {
      final videoDto = PostDto.fromJson({
        'id': 200,
        'user_id': 42,
        'title': '视频笔记',
        'type': 2,
        'video': {'url': 'https://cdn.example.com/v.mp4', 'cover_url': 'https://cdn.example.com/c.jpg'},
      });
      when(
        () => api.list(
          category: any(named: 'category'),
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          userId: any(named: 'userId'),
          isDraft: any(named: 'isDraft'),
        ),
      ).thenAnswer((_) async => _paged([videoDto]));

      final paged = await repo.list();

      expect(paged.list.first.isVideo, isTrue);
      expect(paged.list.first.videoUrl, 'https://cdn.example.com/v.mp4');
      expect(paged.list.first.coverUrl, 'https://cdn.example.com/c.jpg');
    });
  });

  group('PostRepository.detail', () {
    test('有 user 嵌套对象：用 user.toEntity() 作为 author', () async {
      when(() => api.detail(100)).thenAnswer((_) async => _postDtoWithUser);

      final detail = await repo.detail(100);

      expect(detail.post.id, 100);
      expect(detail.post.title, '夏日西瓜图鉴');
      expect(detail.author.id, 42);
      expect(detail.author.userId, 'guagua_001');
      expect(detail.author.nickname, '瓜呱');
      expect(detail.author.bio, '热爱生活');
      expect(detail.author.location, '上海');
    });

    test('无 user 嵌套对象：回退使用 PostDto 顶层字段构造 author', () async {
      when(() => api.detail(100)).thenAnswer((_) async => _postDto);

      final detail = await repo.detail(100);

      expect(detail.post.id, 100);
      expect(detail.author.id, 42);
      expect(detail.author.userId, '42'); 
      expect(detail.author.nickname, '瓜呱');
      expect(detail.author.avatar, 'https://cdn.example.com/a.png');
      expect(detail.author.isVerified, isTrue);
    });
  });

  group('PostRepository.comments', () {
    test('将 PagedData<CommentDto> 转为 PagedData<CommentEntity>', () async {
      when(() => api.comments(100, page: 1, limit: 20)).thenAnswer(
        (_) async => _paged([_commentDto], total: 50, page: 1, hasMore: true),
      );

      final paged = await repo.comments(100);

      expect(paged.list.length, 1);
      expect(paged.total, 50);
      expect(paged.hasMore, isTrue);
      final c = paged.list.first;
      expect(c.id, 200);
      expect(c.postId, 100);
      expect(c.content, '看起来好好吃');
      expect(c.authorId, 50);
      expect(c.authorNickname, '吃货');
      expect(c.replyCount, 3);
      expect(c.liked, isFalse);
    });

    test('透传 page / limit', () async {
      when(() => api.comments(100, page: 3, limit: 10)).thenAnswer(
        (_) async => _paged<CommentDto>([], page: 3, limit: 10),
      );

      await repo.comments(100, page: 3, limit: 10);

      verify(() => api.comments(100, page: 3, limit: 10)).called(1);
    });
  });

  group('PostRepository.replies', () {
    test('将 PagedData<CommentDto> 转为 PagedData<CommentEntity>', () async {
      when(() => api.replies(200, page: 1, limit: 10)).thenAnswer(
        (_) async => _paged([_commentDto], total: 3, page: 1, hasMore: false),
      );

      final paged = await repo.replies(200);

      expect(paged.list.length, 1);
      expect(paged.total, 3);
      expect(paged.hasMore, isFalse);
      expect(paged.list.first.id, 200);
    });
  });

  group('PostRepository.createComment', () {
    test('返回 CommentEntity，透传 parentId', () async {
      when(
        () => api.createComment(100, content: '评论内容', parentId: 200),
      ).thenAnswer((_) async => _commentDto);

      final entity = await repo.createComment(100, content: '评论内容', parentId: 200);

      expect(entity.id, 200);
      expect(entity.postId, 100);
      verify(() => api.createComment(100, content: '评论内容', parentId: 200)).called(1);
    });

    test('无 parentId 透传 null', () async {
      when(
        () => api.createComment(100, content: '评论内容', parentId: null),
      ).thenAnswer((_) async => _commentDto);

      await repo.createComment(100, content: '评论内容');

      verify(() => api.createComment(100, content: '评论内容', parentId: null)).called(1);
    });
  });

  group('PostRepository.deleteComment', () {
    test('委托 api.deleteComment', () async {
      when(() => api.deleteComment(200)).thenAnswer((_) async {});

      await repo.deleteComment(200);

      verify(() => api.deleteComment(200)).called(1);
    });
  });

  group('PostRepository 点赞', () {
    test('likePost：使用 targetType=1', () async {
      when(() => api.like(targetType: 1, targetId: 100)).thenAnswer((_) async => true);

      final result = await repo.likePost(100);

      expect(result, isTrue);
      verify(() => api.like(targetType: 1, targetId: 100)).called(1);
    });

    test('unlikePost：使用 targetType=1', () async {
      when(() => api.unlike(targetType: 1, targetId: 100)).thenAnswer((_) async {});

      await repo.unlikePost(100);

      verify(() => api.unlike(targetType: 1, targetId: 100)).called(1);
    });

    test('likeComment：使用 targetType=2', () async {
      when(() => api.like(targetType: 2, targetId: 200)).thenAnswer((_) async => true);

      final result = await repo.likeComment(200);

      expect(result, isTrue);
      verify(() => api.like(targetType: 2, targetId: 200)).called(1);
    });

    test('unlikeComment：使用 targetType=2', () async {
      when(() => api.unlike(targetType: 2, targetId: 200)).thenAnswer((_) async {});

      await repo.unlikeComment(200);

      verify(() => api.unlike(targetType: 2, targetId: 200)).called(1);
    });
  });

  group('PostRepository 收藏', () {
    test('collect：委托 api.collect', () async {
      when(() => api.collect(100)).thenAnswer((_) async => true);

      final result = await repo.collect(100);

      expect(result, isTrue);
      verify(() => api.collect(100)).called(1);
    });

    test('uncollect：委托 api.uncollect', () async {
      when(() => api.uncollect(100)).thenAnswer((_) async {});

      await repo.uncollect(100);

      verify(() => api.uncollect(100)).called(1);
    });
  });

  group('PostRepository.search', () {
    test('将 PagedData<PostDto> 转为 PagedData<PostEntity>', () async {
      when(
        () => api.search(keyword: '西瓜', page: 1, limit: 20),
      ).thenAnswer((_) async => _paged([_postDto], total: 30, page: 1, hasMore: true));

      final paged = await repo.search(keyword: '西瓜');

      expect(paged.list.length, 1);
      expect(paged.total, 30);
      expect(paged.hasMore, isTrue);
      expect(paged.list.first.title, '夏日西瓜图鉴');
    });

    test('透传 page / limit', () async {
      when(
        () => api.search(keyword: '西瓜', page: 2, limit: 10),
      ).thenAnswer((_) async => _paged<PostDto>([], page: 2, limit: 10));

      await repo.search(keyword: '西瓜', page: 2, limit: 10);

      verifyNever(() => api.search(keyword: '西瓜', page: 2, limit: 20));
      verify(() => api.search(keyword: '西瓜', page: 2, limit: 10)).called(1);
    });
  });

  group('PostRepository.deletePost', () {
    test('委托 api.deletePost', () async {
      when(() => api.deletePost(100)).thenAnswer((_) async {});

      await repo.deletePost(100);

      verify(() => api.deletePost(100)).called(1);
    });
  });

  group('PostRepository.view', () {
    test('委托 api.view（失败静默由 api 处理）', () async {
      when(() => api.view(100)).thenAnswer((_) async {});

      await repo.view(100);

      verify(() => api.view(100)).called(1);
    });
  });

  group('PostRepository.hotTags', () {
    test('委托 api.hotTags 并透传 limit', () async {
      when(() => api.hotTags(limit: 15)).thenAnswer((_) async => ['西瓜', '夏日', '美食']);

      final tags = await repo.hotTags(limit: 15);

      expect(tags, ['西瓜', '夏日', '美食']);
      verify(() => api.hotTags(limit: 15)).called(1);
    });

    test('默认 limit=10', () async {
      when(() => api.hotTags(limit: 10)).thenAnswer((_) async => []);

      await repo.hotTags();

      verify(() => api.hotTags(limit: 10)).called(1);
    });
  });
}
