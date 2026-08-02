import '../../../core/utils/formatters.dart';
import '../domain/chat_entity.dart';

class ChatSessionDto {
  const ChatSessionDto({
    required this.id,
    required this.type,
    required this.name,
    this.avatar = '',
    this.lastMessage = '',
    this.lastMessageTime,
    this.unreadCount = 0,
    this.peerId,
    this.groupId,
    this.lastMessageSender = '',
    this.updatedAt,
  });

  final int id;
  final String type;
  final String name;
  final String avatar;
  final String lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final int? peerId;
  final int? groupId;
  final String lastMessageSender;
  final DateTime? updatedAt;

  factory ChatSessionDto.fromJson(Map<String, dynamic> json) {
    final rawType = json['session_type'] ?? json['type'];
    final typeNum = rawType is num
        ? rawType.toInt()
        : (int.tryParse(rawType?.toString() ?? '') ?? -1);
    final typeStr = typeNum == 2 || rawType == 'group' ? 'group' : 'private';
    return ChatSessionDto(
      id: parseInt(json['id']),
      type: typeStr,
      name: cleanString(
        json['name'] ?? json['nickname'] ?? json['target_nickname'],
      ),
      avatar: cleanString(json['avatar'] ?? json['target_avatar']),
      lastMessage: cleanString(json['last_message'] ?? json['lastMessage']),
      lastMessageTime: tryParseDateTime(
        json['last_message_time'] as String? ??
            json['lastMessageTime'] as String?,
      ),
      unreadCount: parseInt(json['unread_count']),
      peerId: tryParseNum(
        json['peer_id'] ?? json['to_user_id'] ?? json['target_id'],
      )?.toInt(),
      groupId: tryParseNum(json['group_id'])?.toInt(),
      lastMessageSender: cleanString(
        json['last_message_sender'] ?? json['sender_name'],
      ),
      updatedAt: tryParseDateTime(json['updated_at'] as String?),
    );
  }

  ChatSessionEntity toEntity() => ChatSessionEntity(
    id: id,
    type: type,
    name: name,
    avatar: getFullImageUrl(avatar),
    lastMessage: lastMessage,
    lastMessageTime: lastMessageTime,
    unreadCount: unreadCount,
    peerId: peerId,
    groupId: groupId,
    lastMessageSender: lastMessageSender,
    updatedAt: updatedAt,
  );
}

/// 消息 DTO
class ChatMessageDto {
  const ChatMessageDto({
    required this.id,
    required this.sessionId,
    required this.fromUserId,
    required this.type,
    required this.content,
    this.fromNickname = '',
    this.fromAvatar = '',
    this.replyTo,
    this.shareId,
    this.shareTitle,
    this.shareCover,
    this.createdAt,
    this.status = 'sent',
    this.readByPeer = false,
  });

  final int id;
  final int sessionId;
  final int fromUserId;
  final int type;
  final String content;
  final String fromNickname;
  final String fromAvatar;
  final int? replyTo;
  final int? shareId;
  final String? shareTitle;
  final String? shareCover;
  final DateTime? createdAt;
  final String status;
  final bool readByPeer;

  factory ChatMessageDto.fromJson(Map<String, dynamic> json) {
    return ChatMessageDto(
      id: parseInt(json['id']),
      sessionId: parseInt(json['session_id'] ?? json['sessionId']),
      fromUserId: parseInt(json['from_user_id'] ?? json['fromUserId']),
      type: parseInt(json['type'], fallback: 1),
      content: cleanString(json['content']),
      fromNickname: cleanString(
        json['from_nickname'] ?? json['fromNickname'] ?? json['nickname'],
      ),
      fromAvatar: cleanString(
        json['from_avatar'] ?? json['fromAvatar'] ?? json['avatar'],
      ),
      replyTo: tryParseNum(json['reply_to'] ?? json['replyTo'])?.toInt(),
      shareId: tryParseNum(json['share_id'])?.toInt(),
      shareTitle: cleanString(json['share_title']),
      shareCover: cleanString(json['share_cover']),
      createdAt: tryParseDateTime(
        json['created_at'] as String? ?? json['createdAt'] as String?,
      ),
      status: cleanString(json['status']).isEmpty
          ? 'sent'
          : cleanString(json['status']),
      readByPeer:
          (json['read_by_peer'] as bool?) ??
          ((json['read_by_peer'] as num?)?.toInt() ?? 0) == 1,
    );
  }

  factory ChatMessageDto.fromSocket(Map<String, dynamic> json) {
    return ChatMessageDto.fromJson(json);
  }

  ChatMessageEntity toEntity({int? currentUserId}) {
    final status = switch (this.status) {
      'pending' => MessageStatus.pending,
      'failed' => MessageStatus.failed,
      'recalled' => MessageStatus.recalled,
      _ => MessageStatus.sent,
    };
    return ChatMessageEntity(
      id: id,
      sessionId: sessionId,
      fromUserId: fromUserId,
      type: ChatMessageType.fromValue(type),
      content: content,
      fromNickname: fromNickname,
      fromAvatar: getFullImageUrl(fromAvatar),
      replyTo: replyTo,
      shareId: shareId,
      shareTitle: shareTitle,
      shareCover: shareCover != null ? getFullImageUrl(shareCover!) : null,
      status: status,
      createdAt: createdAt,
      isMine: currentUserId != null && fromUserId == currentUserId,
      readByPeer: readByPeer,
    );
  }

  Map<String, dynamic> toSocketPayload({String? eventType}) => {
    'id': id,
    'session_id': sessionId,
    'from_user_id': fromUserId,
    'from_nickname': fromNickname,
    'from_avatar': fromAvatar,
    'content': content,
    'type': type,
    if (replyTo != null) 'reply_to': replyTo,
    if (shareId != null) 'share_id': shareId,
    if (shareTitle != null) 'share_title': shareTitle,
    if (shareCover != null) 'share_cover': shareCover,
    'created_at': createdAt?.toIso8601String(),
  };
}

class CreateSessionRequest {
  const CreateSessionRequest({required this.targetId, required this.type});

  final int targetId;
  final String type;

  Map<String, dynamic> toJson() => {'target_id': targetId, 'type': type};
}

class CreateGroupRequest {
  const CreateGroupRequest({required this.name, required this.memberIds});

  final String name;
  final List<int> memberIds;

  Map<String, dynamic> toJson() => {'name': name, 'member_ids': memberIds};
}

class ChatGroupMemberDto {
  const ChatGroupMemberDto({
    required this.userId,
    required this.nickname,
    this.avatar = '',
    this.role = 'member',
  });

  final int userId;
  final String nickname;
  final String avatar;
  final String role;

  factory ChatGroupMemberDto.fromJson(Map<String, dynamic> json) {
    return ChatGroupMemberDto(
      userId: parseInt(json['user_id'] ?? json['id']),
      nickname: cleanString(json['nickname']),
      avatar: cleanString(json['avatar']),
      role: cleanString(json['role']).isEmpty
          ? 'member'
          : cleanString(json['role']),
    );
  }

  ChatGroupMemberEntity toEntity() => ChatGroupMemberEntity(
    userId: userId,
    nickname: nickname,
    avatar: getFullImageUrl(avatar),
    role: role,
  );
}
