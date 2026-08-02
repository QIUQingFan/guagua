enum NotificationType {
  like,
  comment,
  reply,
  follow,
  collection,
  mention,
  unknown;

  static NotificationType fromCode(String code) {
    switch (code) {
      case 'like':
        return NotificationType.like;
      case 'comment':
        return NotificationType.comment;
      case 'reply':
        return NotificationType.reply;
      case 'follow':
        return NotificationType.follow;
      case 'collection':
        return NotificationType.collection;
      case 'mention':
        return NotificationType.mention;
      default:
        return NotificationType.unknown;
    }
  }
}

class NotificationEntity {
  const NotificationEntity({
    required this.id,
    required this.type,
    required this.senderId,
    required this.senderNickname,
    this.senderUserId = '',
    this.senderAvatar = '',
    this.senderVerified = 0,
    this.postId,
    this.postTitle = '',
    this.postImage = '',
    this.commentContent = '',
    this.targetType = '',
    this.isRead = false,
    this.createdAt,
  });

  final int id;
  final NotificationType type;
  final int senderId;
  final String senderNickname;
  final String senderUserId;
  final String senderAvatar;
  final int senderVerified;
  final int? postId;
  final String postTitle;
  final String postImage;
  final String commentContent;
  final String targetType;
  final bool isRead;
  final DateTime? createdAt;

  NotificationEntity copyWith({
    int? id,
    NotificationType? type,
    int? senderId,
    String? senderNickname,
    String? senderUserId,
    String? senderAvatar,
    int? senderVerified,
    int? postId,
    String? postTitle,
    String? postImage,
    String? commentContent,
    String? targetType,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return NotificationEntity(
      id: id ?? this.id,
      type: type ?? this.type,
      senderId: senderId ?? this.senderId,
      senderNickname: senderNickname ?? this.senderNickname,
      senderUserId: senderUserId ?? this.senderUserId,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      senderVerified: senderVerified ?? this.senderVerified,
      postId: postId ?? this.postId,
      postTitle: postTitle ?? this.postTitle,
      postImage: postImage ?? this.postImage,
      commentContent: commentContent ?? this.commentContent,
      targetType: targetType ?? this.targetType,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

enum NotificationTab { all, like, comment, follow }

extension NotificationTabPath on NotificationTab {
  String get path {
    switch (this) {
      case NotificationTab.all:
        return '/notifications';
      case NotificationTab.like:
        return '/notifications/likes';
      case NotificationTab.comment:
        return '/notifications/comments';
      case NotificationTab.follow:
        return '/notifications/follows';
    }
  }
}
