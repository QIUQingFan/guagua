/// 评论领域实体。
///
/// 后端 `content` 可能含 HTML `<a>` 标签（@提及），[plainContent] 用于纯展示。
class CommentEntity {
  const CommentEntity({
    required this.id,
    required this.postId,
    required this.content,
    required this.authorId,
    required this.authorNickname,
    this.authorUserId = '',
    this.authorAvatar = '',
    this.authorVerified = false,
    this.parentId,
    this.replyCount = 0,
    this.likeCount = 0,
    this.liked = false,
    this.createdAt,
  });

  final int id;
  final int postId;
  final String content;
  final int authorId;
  final String authorNickname;

  /// 评论者的瓜呱号（后端 `user_display_id`），用于跳转用户主页。
  final String authorUserId;
  final String authorAvatar;
  final bool authorVerified;
  final int? parentId;
  final int replyCount;
  final int likeCount;
  final bool liked;
  final DateTime? createdAt;

  /// 移除 HTML 标签，得到纯文本（用于展示与截断）。
  String get plainContent => content
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  CommentEntity copyWith({
    int? id,
    int? postId,
    String? content,
    int? authorId,
    String? authorNickname,
    String? authorUserId,
    String? authorAvatar,
    bool? authorVerified,
    int? parentId,
    int? replyCount,
    int? likeCount,
    bool? liked,
    DateTime? createdAt,
  }) {
    return CommentEntity(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      content: content ?? this.content,
      authorId: authorId ?? this.authorId,
      authorNickname: authorNickname ?? this.authorNickname,
      authorUserId: authorUserId ?? this.authorUserId,
      authorAvatar: authorAvatar ?? this.authorAvatar,
      authorVerified: authorVerified ?? this.authorVerified,
      parentId: parentId ?? this.parentId,
      replyCount: replyCount ?? this.replyCount,
      likeCount: likeCount ?? this.likeCount,
      liked: liked ?? this.liked,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
