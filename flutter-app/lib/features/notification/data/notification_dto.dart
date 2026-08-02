import '../../../core/utils/formatters.dart';
import '../domain/notification_entity.dart';

class NotificationDto {
  const NotificationDto({
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
    this.isRead = 0,
    this.createdAt,
  });

  final int id;
  final String type;
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
  final int isRead;
  final DateTime? createdAt;

  factory NotificationDto.fromJson(Map<String, dynamic> json) {
    return NotificationDto(
      id: parseInt(json['id']),
      type: cleanString(json['type']),
      senderId: parseInt(json['sender_id']),
      senderUserId: cleanString(
        json['from_user_id'] ??
            json['sender_user_id'] ??
            json['sender_account'],
      ),
      senderNickname: cleanString(json['sender_nickname']),
      senderAvatar: cleanString(json['sender_avatar']),
      senderVerified: parseInt(json['sender_verified']),
      postId: tryParseNum(json['post_id'])?.toInt(),
      postTitle: cleanString(json['post_title']),
      postImage: cleanString(json['post_image']),
      commentContent: cleanString(json['comment_content']),
      targetType: cleanString(json['target_type']),
      isRead: parseInt(json['is_read']),
      createdAt: tryParseDateTime(json['created_at'] as String?),
    );
  }

  NotificationEntity toEntity() => NotificationEntity(
    id: id,
    type: NotificationType.fromCode(type),
    senderId: senderId,
    senderNickname: senderNickname,
    senderUserId: senderUserId,
    senderAvatar: senderAvatar,
    senderVerified: senderVerified,
    postId: postId,
    postTitle: postTitle,
    postImage: postImage,
    commentContent: commentContent,
    targetType: targetType,
    isRead: isRead == 1,
    createdAt: createdAt,
  );
}
