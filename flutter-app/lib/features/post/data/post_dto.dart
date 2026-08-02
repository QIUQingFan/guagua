import '../../../core/utils/formatters.dart';
import '../../../shared/domain/comment_entity.dart';
import '../../../shared/domain/post_entity.dart';
import '../../auth/data/auth_dto.dart' show UserDto;

class PostDto {
  const PostDto({
    required this.id,
    required this.userId,
    required this.title,
    this.content = '',
    this.type = 1,
    this.categoryId,
    this.images = const [],
    this.videoUrl,
    this.coverUrl,
    this.video,
    this.tags = const [],
    this.nickname = '',
    this.userAvatar = '',
    this.userDisplayId = '',
    this.verified = 0,
    this.viewCount = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    this.collectCount = 0,
    this.isLiked = false,
    this.isCollected = false,
    this.createdAt,
    this.user,
  });

  final int id;
  final int userId;
  final String title;
  final String content;
  final int type;
  final int? categoryId;
  final List<String> images;
  final String? videoUrl;
  final String? coverUrl;
  final VideoDto? video;
  final List<TagDto> tags;
  final String nickname;
  final String userAvatar;

  final String userDisplayId;
  final int verified;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final int collectCount;
  final bool isLiked;
  final bool isCollected;
  final DateTime? createdAt;
  final UserDto? user;

  factory PostDto.fromJson(Map<String, dynamic> json) {
    final video = json['video'] is Map<String, dynamic>
        ? VideoDto.fromJson(json['video'] as Map<String, dynamic>)
        : null;
    final tagsRaw = json['tags'];
    List<TagDto> tags;
    if (tagsRaw is List) {
      tags = tagsRaw
          .map(
            (t) => t is String
                ? TagDto(id: 0, name: t)
                : TagDto.fromJson(t as Map<String, dynamic>),
          )
          .toList();
    } else {
      tags = const [];
    }
    return PostDto(
      id: (json['id'] as num).toInt(),
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      title: cleanString(json['title']),
      content: cleanString(json['content']),
      type: (json['type'] as num?)?.toInt() ?? 1,
      categoryId: (json['category_id'] as num?)?.toInt(),
      images: (json['images'] as List<dynamic>? ?? const [])
          .map((e) => cleanString(e))
          .toList(),
      videoUrl: cleanString(json['video_url'] ?? video?.url),
      coverUrl: cleanString(json['cover_url'] ?? video?.coverUrl),
      video: video,
      tags: tags,
      nickname: cleanString(json['nickname'] ?? json['user']?['nickname']),
      userAvatar: cleanString(json['user_avatar'] ?? json['user']?['avatar']),
      userDisplayId: cleanString(
        json['user_display_id'] ??
            json['display_id'] ??
            json['author_account'] ??
            json['username'] ??
            json['user_name'] ??
            json['account'] ??
            json['guagua_id'] ??
            json['guaguaId'] ??
            json['user']?['user_id'] ??
            json['user']?['display_id'] ??
            json['user']?['username'] ??
            json['user']?['account'] ??
            (json['user_id']?.toString()),
      ),
      verified:
          (json['verified'] as num? ?? json['user']?['verified'] as num?)
              ?.toInt() ??
          0,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      collectCount: (json['collect_count'] as num?)?.toInt() ?? 0,
      isLiked:
          (json['isLiked'] as bool?) ?? (json['is_liked'] as bool?) ?? false,
      isCollected:
          (json['isCollected'] as bool?) ??
          (json['is_collected'] as bool?) ??
          false,
      createdAt: tryParseDateTime(json['created_at'] as String?),
      user: json['user'] is Map<String, dynamic>
          ? UserDto.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }

  PostEntity toEntity() => PostEntity(
    id: id,
    authorId: userId,
    authorNickname: nickname,
    authorAvatar: getFullImageUrl(userAvatar),
    authorVerified: verified == 1,
    title: title,
    content: content,
    isVideo: type == 2,
    imageUrls: images.map(getFullImageUrl).toList(),
    videoUrl: getFullImageUrl(videoUrl ?? ''),
    coverUrl: getFullImageUrl(coverUrl ?? ''),
    categoryId: categoryId,
    tags: tags.map((t) => t.name).toList(),
    viewCount: viewCount,
    likeCount: likeCount,
    commentCount: commentCount,
    collectCount: collectCount,
    liked: isLiked,
    collected: isCollected,
    createdAt: createdAt,
  );
}

class VideoDto {
  const VideoDto({this.url = '', this.coverUrl});

  final String url;
  final String? coverUrl;

  factory VideoDto.fromJson(Map<String, dynamic> json) {
    return VideoDto(
      url: (json['url'] ?? '').toString(),
      coverUrl: (json['coverUrl'] ?? json['cover_url'])?.toString(),
    );
  }
}

class TagDto {
  const TagDto({required this.id, required this.name});
  final int id;
  final String name;

  factory TagDto.fromJson(Map<String, dynamic> json) {
    return TagDto(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
    );
  }
}

class CategoryDto {
  const CategoryDto({
    required this.id,
    required this.name,
    this.title = '',
    this.postCount = 0,
    this.createdAt,
  });

  final int id;
  final String name;
  final String title;
  final int postCount;
  final DateTime? createdAt;

  factory CategoryDto.fromJson(Map<String, dynamic> json) {
    return CategoryDto(
      id: (json['id'] as num).toInt(),
      name: (json['name'] ?? '').toString(),
      title: (json['category_title'] ?? '').toString(),
      postCount: (json['post_count'] as num?)?.toInt() ?? 0,
      createdAt: tryParseDateTime(json['created_at'] as String?),
    );
  }

  CategoryEntity toEntity() =>
      CategoryEntity(id: id, name: name, title: title, postCount: postCount);
}

class CommentDto {
  const CommentDto({
    required this.id,
    required this.content,
    required this.userId,
    required this.nickname,
    this.userDisplayId = '',
    this.userAvatar = '',
    this.verified = 0,
    required this.postId,
    this.parentId,
    this.replyCount = 0,
    this.liked = false,
    this.createdAt,
  });

  final int id;
  final String content;
  final int userId;
  final String nickname;

  final String userDisplayId;
  final String userAvatar;
  final int verified;
  final int postId;
  final int? parentId;
  final int replyCount;
  final bool liked;
  final DateTime? createdAt;

  factory CommentDto.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return CommentDto(
      id: parseInt(json['id']),
      content: cleanString(json['content']),
      userId: parseInt(json['user_id'] ?? user['id']),
      nickname: cleanString(json['nickname'] ?? user['nickname']),
      userDisplayId: cleanString(
        json['user_display_id'] ??
            json['display_id'] ??
            json['author_account'] ??
            json['sender_user_id'] ??
            json['username'] ??
            json['user_name'] ??
            json['account'] ??
            json['guagua_id'] ??
            user['user_id'] ??
            user['display_id'] ??
            user['username'] ??
            user['account'] ??
            (json['user_id']?.toString()),
      ),
      userAvatar: cleanString(json['user_avatar'] ?? user['avatar']),
      verified: parseInt(json['verified'] ?? user['verified']),
      postId: parseInt(json['post_id']),
      parentId: tryParseNum(json['parent_id'])?.toInt(),
      replyCount: parseInt(json['reply_count']),
      liked: (json['liked'] as bool?) ?? false,
      createdAt: tryParseDateTime(json['created_at'] as String?),
    );
  }

  CommentEntity toEntity() => CommentEntity(
    id: id,
    postId: postId,
    content: content,
    authorId: userId,
    authorNickname: nickname,
    authorUserId: userDisplayId,
    authorAvatar: getFullImageUrl(userAvatar),
    authorVerified: verified == 1,
    parentId: parentId,
    replyCount: replyCount,
    liked: liked,
    createdAt: createdAt,
  );
}

class LikeResultDto {
  const LikeResultDto({required this.liked});
  final bool liked;
  factory LikeResultDto.fromJson(Map<String, dynamic> json) =>
      LikeResultDto(liked: (json['liked'] as bool?) ?? false);
}

class CollectResultDto {
  const CollectResultDto({required this.collected});
  final bool collected;
  factory CollectResultDto.fromJson(Map<String, dynamic> json) =>
      CollectResultDto(collected: (json['collected'] as bool?) ?? false);
}
