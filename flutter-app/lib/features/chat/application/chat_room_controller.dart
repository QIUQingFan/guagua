import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/socket/socket_event_bus.dart';
import '../../../core/socket/socket_providers.dart';
import '../../auth/application/auth_controller.dart' show currentUserProvider;
import '../data/chat_repository.dart';
import '../domain/chat_entity.dart';
import 'chat_list_controller.dart' show chatListControllerProvider;

/// 聊天窗状态
class ChatRoomState {
  const ChatRoomState({
    this.messages = const [],
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
    this.replyTarget,
    this.connected = false,
  });

  final List<ChatMessageEntity> messages;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;
  final ChatMessageEntity? replyTarget;
  final bool connected;

  bool get isEmpty => messages.isEmpty && !loading;

  ChatRoomState copyWith({
    List<ChatMessageEntity>? messages,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    ChatMessageEntity? replyTarget,
    bool? connected,
    bool clearError = false,
    bool clearReply = false,
  }) {
    return ChatRoomState(
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      replyTarget: clearReply ? null : (replyTarget ?? this.replyTarget),
      connected: connected ?? this.connected,
    );
  }
}

class ChatRoomController extends FamilyNotifier<ChatRoomState, int> {
  final List<StreamSubscription> _subs = [];
  int _page = 1;

  @override
  ChatRoomState build(int sessionId) {
    _subscribe(sessionId);
    Future.microtask(() => loadInitial(sessionId));
    return const ChatRoomState(loading: true);
  }

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  void _subscribe(int sessionId) {
    final socket = ref.read(socketServiceProvider);

    _subs.add(
      socket.on('private:message').listen((event) {
        _onIncoming(event.data as Map<String, dynamic>?, sessionId);
      }),
    );
    _subs.add(
      socket.on('group:message').listen((event) {
        _onIncoming(event.data as Map<String, dynamic>?, sessionId);
      }),
    );
    _subs.add(
      socket.on('private:recall').listen((event) {
        _onRecall(event.data as Map<String, dynamic>?, sessionId);
      }),
    );
    _subs.add(
      socket.on('group:recall').listen((event) {
        _onRecall(event.data as Map<String, dynamic>?, sessionId);
      }),
    );
    _subs.add(
      socket.on('message:read').listen((event) {
        _onMessageRead(event.data as Map<String, dynamic>?, sessionId);
      }),
    );
    _subs.add(
      socket.connectionStateStream.listen((s) {
        state = state.copyWith(connected: s == SocketConnectionState.connected);
      }),
    );

    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      _subs.clear();
    });
  }

  Future<void> loadInitial(int sessionId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final paged = await _repo.messages(sessionId, page: 1);
      _page = 1;
      state = ChatRoomState(
        messages: paged.list.reversed.toList(), 
        hasMore: paged.hasMore,
        connected: state.connected,
      );
      _markUnreadAsRead(sessionId);
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore(int sessionId) async {
    if (state.loadingMore || !state.hasMore || state.loading) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final nextPage = _page + 1;
      final paged = await _repo.messages(sessionId, page: nextPage);
      _page = nextPage;
      state = state.copyWith(
        messages: [...paged.list.reversed, ...state.messages],
        hasMore: paged.hasMore,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }

  /// 发送文本消息
  Future<void> sendText(
    int sessionId, {
    required String content,
    ChatMessageType type = ChatMessageType.text,
    int? shareId,
    String? shareTitle,
    String? shareCover,
  }) async {
    final text = content.trim();
    if (text.isEmpty) return;

    final current = ref.read(currentUserProvider);
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final reply = state.replyTarget;

    final pending = ChatMessageEntity(
      id: tempId,
      sessionId: sessionId,
      fromUserId: current?.id ?? 0,
      type: type,
      content: text,
      fromNickname: current?.nickname ?? '',
      fromAvatar: current?.avatar ?? '',
      replyTo: reply?.id,
      replyToContent: reply?.content,
      replyToNickname: reply?.fromNickname,
      shareId: shareId,
      shareTitle: shareTitle,
      shareCover: shareCover,
      status: MessageStatus.pending,
      createdAt: DateTime.now(),
      isMine: true,
    );

    state = state.copyWith(
      messages: [...state.messages, pending],
      clearReply: true,
    );

    final socket = ref.read(socketServiceProvider);
    final session = _sessionInfo(sessionId);
    final event = session?.isGroup == true
        ? 'group:message'
        : 'private:message';
    final payload = {
      'id': tempId,
      'session_id': sessionId,
      'content': text,
      'type': type.value,
      if (reply != null) 'reply_to': reply.id,
      if (shareId != null) 'share_id': shareId,
      if (shareTitle != null) 'share_title': shareTitle,
      if (shareCover != null) 'share_cover': shareCover,
      if (session?.groupId != null) 'group_id': session?.groupId,
      if (session?.peerId != null) 'to_user_id': session?.peerId,
      'created_at': DateTime.now().toIso8601String(),
    };

    try {
      socket.emit(
        event,
        payload,
        ack: (response) {
          _onAck(tempId, response);
        },
      );
    } catch (_) {
      _markFailed(tempId);
    }
  }

  /// 撤回消息
  Future<void> recall(int sessionId, ChatMessageEntity message) async {
    final age = message.createdAt != null
        ? DateTime.now().difference(message.createdAt!)
        : Duration.zero;
    if (age.inSeconds > 120) return;

    final socket = ref.read(socketServiceProvider);
    final session = _sessionInfo(sessionId);
    final event = session?.isGroup == true ? 'group:recall' : 'private:recall';
    socket.emitNoAck(event, {
      'message_id': message.id,
      if (session?.groupId != null) 'group_id': session?.groupId,
      'session_id': sessionId,
    });

    final messages = state.messages.map((m) {
      if (m.id == message.id) {
        return m.copyWith(status: MessageStatus.recalled);
      }
      return m;
    }).toList();
    state = state.copyWith(messages: messages);

    try {
      await _repo.recallMessage(message.id);
    } catch (_) {}
  }

  /// 引用
  void setReply(ChatMessageEntity? target) {
    state = state.copyWith(replyTarget: target, clearReply: target == null);
  }

  /// 重发失败消息
  Future<void> resend(int sessionId, ChatMessageEntity message) async {
    if (message.status != MessageStatus.failed) return;
    final messages = state.messages.where((m) => m.id != message.id).toList();
    state = state.copyWith(messages: messages);
    await sendText(
      sessionId,
      content: message.content,
      type: message.type,
      shareId: message.shareId,
      shareTitle: message.shareTitle,
      shareCover: message.shareCover,
    );
  }

  void _onIncoming(Map<String, dynamic>? data, int sessionId) {
    if (data == null) return;
    final msgSessionId =
        (data['session_id'] as num?)?.toInt() ??
        (data['sessionId'] as num?)?.toInt();
    if (msgSessionId != sessionId) return;
    final entity = _repo.parseSocketMessage(data);
    if (state.messages.any((m) => m.id == entity.id)) return;
    state = state.copyWith(messages: [...state.messages, entity]);
    if (!entity.isMine) {
      _markUnreadAsRead(sessionId);
    }
  }

  void _onRecall(Map<String, dynamic>? data, int sessionId) {
    if (data == null) return;
    final messageId =
        (data['message_id'] as num?)?.toInt() ??
        (data['messageId'] as num?)?.toInt();
    if (messageId == null) return;
    final messages = state.messages.map((m) {
      if (m.id == messageId) {
        return m.copyWith(status: MessageStatus.recalled);
      }
      return m;
    }).toList();
    state = state.copyWith(messages: messages);
  }

  void _onAck(int tempId, dynamic response) {
    int newId = tempId;
    if (response is Map) {
      final data = response['data'];
      final Map<String, dynamic> msg = data is Map<String, dynamic>
          ? data
          : response as Map<String, dynamic>;
      newId = (msg['id'] as num?)?.toInt() ?? tempId;
    }
    final messages = state.messages.map((m) {
      if (m.id == tempId) {
        return m.copyWith(id: newId, status: MessageStatus.sent);
      }
      return m;
    }).toList();
    state = state.copyWith(messages: messages);
  }

  void _markUnreadAsRead(int sessionId) {
    final unreadFromPeer = state.messages
        .where((m) => !m.isMine && m.status == MessageStatus.sent)
        .toList();
    if (unreadFromPeer.isEmpty) return;

    final lastId = unreadFromPeer.last.id;
    final socket = ref.read(socketServiceProvider);
    final session = _sessionInfo(sessionId);
    socket.emitNoAck('message:read', {
      'session_id': sessionId,
      'last_read_message_id': lastId,
      if (session?.groupId != null) 'group_id': session?.groupId,
    });

    Future.microtask(() async {
      try {
        await _repo.markRead(sessionId);
      } catch (_) {}
    });
  }

  void _onMessageRead(Map<String, dynamic>? data, int sessionId) {
    if (data == null) return;
    final msgSessionId =
        (data['session_id'] as num?)?.toInt() ??
        (data['sessionId'] as num?)?.toInt();
    if (msgSessionId != null && msgSessionId != sessionId) return;

    final lastReadId =
        (data['last_read_message_id'] as num?)?.toInt() ??
        (data['message_id'] as num?)?.toInt() ??
        (data['messageId'] as num?)?.toInt();
    if (lastReadId == null) return;

    final messages = state.messages.map((m) {
      if (m.isMine && m.id <= lastReadId && m.status == MessageStatus.sent) {
        return m.copyWith(readByPeer: true);
      }
      return m;
    }).toList();
    state = state.copyWith(messages: messages);
  }

  void _markFailed(int tempId) {
    final messages = state.messages.map((m) {
      if (m.id == tempId) {
        return m.copyWith(status: MessageStatus.failed);
      }
      return m;
    }).toList();
    state = state.copyWith(messages: messages);
  }

  ChatSessionEntity? _sessionInfo(int sessionId) {
    final list = ref.read(chatListControllerProvider).sessions;
    for (final s in list) {
      if (s.id == sessionId) return s;
    }
    return null;
  }
}

final chatRoomControllerProvider =
    NotifierProvider.family<ChatRoomController, ChatRoomState, int>(
      ChatRoomController.new,
    );
