import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/services/local_notification_service.dart';
import '../../../core/socket/socket_providers.dart';
import '../../auth/application/auth_controller.dart' show currentUserProvider;
import '../../user/data/user_api.dart';
import '../../user/data/user_repository.dart' show userApiProvider;
import '../data/chat_repository.dart';
import '../domain/chat_entity.dart';

/// 会话列表状态
class ChatListState {
  const ChatListState({
    this.sessions = const [],
    this.loading = false,
    this.error,
    this.totalUnread = 0,
  });

  final List<ChatSessionEntity> sessions;
  final bool loading;
  final Object? error;
  final int totalUnread;

  bool get isEmpty => sessions.isEmpty && !loading;

  ChatListState copyWith({
    List<ChatSessionEntity>? sessions,
    bool? loading,
    Object? error,
    int? totalUnread,
    bool clearError = false,
  }) {
    return ChatListState(
      sessions: sessions ?? this.sessions,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      totalUnread: totalUnread ?? this.totalUnread,
    );
  }
}

class ChatListController extends Notifier<ChatListState> {
  StreamSubscription? _privateSub;
  StreamSubscription? _groupSub;
  StreamSubscription? _sessionUpdateSub;

  @override
  ChatListState build() {
    ref.watch(socketServiceProvider);

    _subscribeSocketEvents();
    Future.microtask(refresh);
    return const ChatListState(loading: true);
  }

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  UserApi get _userApi => ref.read(userApiProvider);

  Future<int?> findUserIdByGuaguaId(String guaguaId) async {
    final keyword = guaguaId.trim();
    if (keyword.isEmpty) return null;
    try {
      final paged = await _userApi.search(keyword: keyword, page: 1, limit: 20);
      for (final u in paged.list) {
        if (u.userId == keyword) return u.id;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void _subscribeSocketEvents() {
    final socket = ref.read(socketServiceProvider);
    _privateSub = socket.on('private:message').listen((event) {
      _onIncomingMessage(event.data as Map<String, dynamic>?);
    });
    _groupSub = socket.on('group:message').listen((event) {
      _onIncomingMessage(event.data as Map<String, dynamic>?);
    });
    _sessionUpdateSub = socket.on('session:update').listen((event) {
      _onSessionUpdate(event.data as Map<String, dynamic>?);
    });
    ref.onDispose(() {
      _privateSub?.cancel();
      _groupSub?.cancel();
      _sessionUpdateSub?.cancel();
    });
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final list = await _repo.sessions();
      final total = list.fold<int>(0, (s, e) => s + e.unreadCount);
      state = ChatListState(sessions: list, totalUnread: total);
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e);
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  /// 收到新消息：更新对应会话的最后消息和未读数
  void _onIncomingMessage(Map<String, dynamic>? data) {
    if (data == null) return;
    final sessionId =
        (data['session_id'] as num?)?.toInt() ??
        (data['sessionId'] as num?)?.toInt();
    if (sessionId == null) return;
    final content = (data['content'] ?? '').toString();
    final fromNickname = (data['from_nickname'] ?? data['nickname'] ?? '')
        .toString();
    final fromUserId = (data['from_user_id'] as num?)?.toInt() ?? 0;

    final isMine = _isMine(fromUserId);

    final sessions = state.sessions.map((s) {
      if (s.id != sessionId) return s;
      return s.copyWith(
        lastMessage: content,
        lastMessageSender: fromNickname,
        lastMessageTime: DateTime.now(),
        unreadCount: isMine ? s.unreadCount : s.unreadCount + 1,
        updatedAt: DateTime.now(),
      );
    }).toList();

    if (!sessions.any((s) => s.id == sessionId)) {
      Future.microtask(refresh);
      if (!isMine) _maybeNotifyBackground(sessionId, fromNickname, content);
      return;
    }
    state = state.copyWith(
      sessions: sessions,
      totalUnread: sessions.fold<int>(0, (s, e) => s + e.unreadCount),
    );

    if (!isMine) _maybeNotifyBackground(sessionId, fromNickname, content);
  }

  Future<void> _maybeNotifyBackground(
    int sessionId,
    String fromNickname,
    String content,
  ) async {
    final notif = ref.read(localNotificationServiceProvider);
    if (notif.isForeground) return;
    final title = fromNickname.isEmpty ? '新消息' : fromNickname;
    final payload = LocalNotificationService.encodePayload({
      'sessionId': sessionId,
      'route': '/chat/$sessionId',
    });
    await notif.show(
      id: sessionId,
      title: title,
      body: content,
      payload: payload,
    );
  }

  void _onSessionUpdate(Map<String, dynamic>? data) {
    if (data == null) return;
    final sessionId =
        (data['sessionId'] as num?)?.toInt() ??
        (data['session_id'] as num?)?.toInt();
    if (sessionId == null) return;
    final lastMessage = (data['lastMessage'] ?? data['last_message'] ?? '')
        .toString();
    final unread = (data['unreadCount'] ?? data['unread_count']) as num?;
    final unreadCount = unread?.toInt();

    final sessions = state.sessions.map((s) {
      if (s.id != sessionId) return s;
      return s.copyWith(
        lastMessage: lastMessage.isEmpty ? s.lastMessage : lastMessage,
        unreadCount: unreadCount ?? s.unreadCount,
        updatedAt: DateTime.now(),
      );
    }).toList();
    state = state.copyWith(
      sessions: sessions,
      totalUnread: sessions.fold<int>(0, (s, e) => s + e.unreadCount),
    );
  }

  Future<void> clearUnread(int sessionId) async {
    final sessions = state.sessions.map((s) {
      if (s.id != sessionId) return s;
      return s.copyWith(unreadCount: 0);
    }).toList();
    state = state.copyWith(
      sessions: sessions,
      totalUnread: sessions.fold<int>(0, (s, e) => s + e.unreadCount),
    );
    try {
      await _repo.markRead(sessionId);
    } catch (_) {}
  }

  Future<ChatSessionEntity?> ensurePrivateSession(int targetUserId) async {
    try {
      return await _repo.createSession(targetId: targetUserId, type: 'private');
    } catch (_) {
      return null;
    }
  }

  bool _isMine(int fromUserId) {
    final current = ref.read(currentUserProvider)?.id;
    return current != null && fromUserId == current;
  }
}

final chatListControllerProvider =
    NotifierProvider<ChatListController, ChatListState>(ChatListController.new);
