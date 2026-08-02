import '../../../core/utils/formatters.dart';

/// 消息类型
enum ChatMessageType {
  text(1),
  image(2),
  emoji(3),
  shareCard(4),
  quote(5),
  system(99);

  const ChatMessageType(this.value);
  final int value;

  static ChatMessageType fromValue(int? v) {
    return ChatMessageType.values.firstWhere(
      (e) => e.value == v,
      orElse: () => ChatMessageType.text,
    );
  }
}

enum MessageStatus { pending, sent, failed, recalled }

class ChatSessionEntity {
  const ChatSessionEntity({
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

  bool get isGroup => type == 'group';

  ChatSessionEntity copyWith({
    int? id,
    String? type,
    String? name,
    String? avatar,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    int? peerId,
    int? groupId,
    String? lastMessageSender,
    DateTime? updatedAt,
  }) {
    return ChatSessionEntity(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      peerId: peerId ?? this.peerId,
      groupId: groupId ?? this.groupId,
      lastMessageSender: lastMessageSender ?? this.lastMessageSender,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ChatMessageEntity {
  const ChatMessageEntity({
    required this.id,
    required this.sessionId,
    required this.fromUserId,
    required this.type,
    required this.content,
    this.fromNickname = '',
    this.fromAvatar = '',
    this.replyTo,
    this.replyToContent,
    this.replyToNickname,
    this.shareId,
    this.shareTitle,
    this.shareCover,
    this.status = MessageStatus.sent,
    this.createdAt,
    this.isMine = false,
    this.readByPeer = false,
  });

  final int id;
  final int sessionId;
  final int fromUserId;
  final ChatMessageType type;
  final String content;
  final String fromNickname;
  final String fromAvatar;
  final int? replyTo;
  final String? replyToContent;
  final String? replyToNickname;
  final int? shareId;
  final String? shareTitle;
  final String? shareCover;
  final MessageStatus status;
  final DateTime? createdAt;
  final bool isMine;

  final bool readByPeer;

  String get displayTime => Formatters.dateTime(createdAt);

  ChatMessageEntity copyWith({
    int? id,
    int? sessionId,
    int? fromUserId,
    ChatMessageType? type,
    String? content,
    String? fromNickname,
    String? fromAvatar,
    int? replyTo,
    String? replyToContent,
    String? replyToNickname,
    int? shareId,
    String? shareTitle,
    String? shareCover,
    MessageStatus? status,
    DateTime? createdAt,
    bool? isMine,
    bool? readByPeer,
  }) {
    return ChatMessageEntity(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      fromUserId: fromUserId ?? this.fromUserId,
      type: type ?? this.type,
      content: content ?? this.content,
      fromNickname: fromNickname ?? this.fromNickname,
      fromAvatar: fromAvatar ?? this.fromAvatar,
      replyTo: replyTo ?? this.replyTo,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToNickname: replyToNickname ?? this.replyToNickname,
      shareId: shareId ?? this.shareId,
      shareTitle: shareTitle ?? this.shareTitle,
      shareCover: shareCover ?? this.shareCover,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      isMine: isMine ?? this.isMine,
      readByPeer: readByPeer ?? this.readByPeer,
    );
  }
}

class ChatGroupMemberEntity {
  const ChatGroupMemberEntity({
    required this.userId,
    required this.nickname,
    this.avatar = '',
    this.role = 'member', 
  });

  final int userId;
  final String nickname;
  final String avatar;
  final String role;

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin' || isOwner;
}
