import 'user_entity.dart';

/// 笔记领域实体。
///
/// 字段归一化为 camelCase；后端 `collect_count` → [collectCount]，
/// 后端 `tags` 为 `[{id,name}]` → [tags] 为字符串列表（仅取 name）。
class PostEntity {
  const PostEntity({
    required this.id,
    required this.authorId,
    required this.authorNickname,
    this.authorAvatar = '',
    this.authorVerified = false,
    required this.title,
    this.content = '',
    required this.isVideo,
    this.imageUrls = const [],
    this.videoUrl = '',
    this.coverUrl = '',
    this.categoryId,
    this.tags = const [],
    this.viewCount = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    this.collectCount = 0,
    this.liked = false,
    this.collected = false,
    this.createdAt,
  });

  final int id;
  final int authorId;
  final String authorNickname;
  final String authorAvatar;
  final bool authorVerified;
  final String title;
  final String content;
  final bool isVideo;

  final List<String> imageUrls;
  final String videoUrl;
  final String coverUrl;
  final int? categoryId;
  final List<String> tags;

  final int viewCount;
  final int likeCount;
  final int commentCount;
  final int collectCount;
  final bool liked;
  final bool collected;
  final DateTime? createdAt;

  /// 卡片封面：视频取 [coverUrl]，图文取首图。
  String get cover => isVideo ? (coverUrl.isEmpty ? (imageUrls.isNotEmpty ? imageUrls.first : '') : coverUrl) : (imageUrls.isNotEmpty ? imageUrls.first : '');

  /// 移除 HTML 标签，得到纯文本标题（后端 title 可能含 `<p>` 等标签）。
  String get plainTitle => title.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  PostEntity copyWith({
    int? id,
    int? authorId,
    String? authorNickname,
    String? authorAvatar,
    bool? authorVerified,
    String? title,
    String? content,
    bool? isVideo,
    List<String>? imageUrls,
    String? videoUrl,
    String? coverUrl,
    int? categoryId,
    List<String>? tags,
    int? viewCount,
    int? likeCount,
    int? commentCount,
    int? collectCount,
    bool? liked,
    bool? collected,
    DateTime? createdAt,
  }) {
    return PostEntity(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorNickname: authorNickname ?? this.authorNickname,
      authorAvatar: authorAvatar ?? this.authorAvatar,
      authorVerified: authorVerified ?? this.authorVerified,
      title: title ?? this.title,
      content: content ?? this.content,
      isVideo: isVideo ?? this.isVideo,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrl: videoUrl ?? this.videoUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      categoryId: categoryId ?? this.categoryId,
      tags: tags ?? this.tags,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      collectCount: collectCount ?? this.collectCount,
      liked: liked ?? this.liked,
      collected: collected ?? this.collected,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// 笔记详情：含完整作者信息与扩展字段。
class PostDetailEntity {
  const PostDetailEntity({
    required this.post,
    required this.author,
  });

  final PostEntity post;
  final UserEntity author;

  PostDetailEntity copyWith({PostEntity? post, UserEntity? author}) {
    return PostDetailEntity(post: post ?? this.post, author: author ?? this.author);
  }
}

/// 分类（频道）实体。
class CategoryEntity {
  const CategoryEntity({
    required this.id,
    required this.name,
    this.title = '',
    this.postCount = 0,
  });

  final int id;
  final String name;
  final String title;
  final int postCount;
}
