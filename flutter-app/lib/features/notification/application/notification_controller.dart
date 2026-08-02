import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_notification_service.dart';
import '../../../core/socket/socket_providers.dart';
import '../../../shared/providers/toast_controller.dart';
import '../data/notification_dto.dart';
import '../data/notification_repository.dart';
import '../domain/notification_entity.dart';

class _PagedState {
  const _PagedState({
    this.list = const [],
    this.page = 1,
    this.hasMore = true,
    this.loading = false,
    this.initialized = false,
  });

  final List<NotificationEntity> list;
  final int page;
  final bool hasMore;
  final bool loading;
  final bool initialized;

  _PagedState copyWith({
    List<NotificationEntity>? list,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? initialized,
  }) {
    return _PagedState(
      list: list ?? this.list,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      initialized: initialized ?? this.initialized,
    );
  }
}

class NotificationState {
  const NotificationState({
    this.all = const _PagedState(),
    this.like = const _PagedState(),
    this.comment = const _PagedState(),
    this.follow = const _PagedState(),
    this.activeTab = NotificationTab.all,
    this.unreadCount = 0,
    this.loading = false,
    this.error,
  });

  final _PagedState all;
  final _PagedState like;
  final _PagedState comment;
  final _PagedState follow;
  final NotificationTab activeTab;
  final int unreadCount;
  final bool loading;
  final Object? error;

  NotificationState copyWith({
    _PagedState? all,
    _PagedState? like,
    _PagedState? comment,
    _PagedState? follow,
    NotificationTab? activeTab,
    int? unreadCount,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) {
    return NotificationState(
      all: all ?? this.all,
      like: like ?? this.like,
      comment: comment ?? this.comment,
      follow: follow ?? this.follow,
      activeTab: activeTab ?? this.activeTab,
      unreadCount: unreadCount ?? this.unreadCount,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  _PagedState currentTab(NotificationTab tab) {
    switch (tab) {
      case NotificationTab.all:
        return all;
      case NotificationTab.like:
        return like;
      case NotificationTab.comment:
        return comment;
      case NotificationTab.follow:
        return follow;
    }
  }
}

class NotificationController extends Notifier<NotificationState> {
  StreamSubscription? _notificationSub;

  @override
  NotificationState build() {
    ref.watch(socketServiceProvider);

    _subscribeSocketEvents();
    _init();
    return const NotificationState();
  }

  void _subscribeSocketEvents() {
    final socket = ref.read(socketServiceProvider);
    _notificationSub = socket.on('notification:new').listen((event) {
      _onNewNotification(event.data as Map<String, dynamic>?);
    });
    ref.onDispose(() {
      _notificationSub?.cancel();
    });
  }

  void _onNewNotification(Map<String, dynamic>? data) {
    if (data == null) return;
    final NotificationEntity entity;
    try {
      entity = NotificationDto.fromJson(data).toEntity();
    } catch (_) {
      state = state.copyWith(unreadCount: state.unreadCount + 1);
      ref.read(toastControllerProvider).show('收到一条新通知');
      return;
    }

    final newUnread = state.unreadCount + 1;

    if (state.all.initialized) {
      final newAllList = [entity, ...state.all.list];
      state = state.copyWith(
        all: state.all.copyWith(list: newAllList),
        unreadCount: newUnread,
      );
    } else {
      state = state.copyWith(unreadCount: newUnread);
    }

    final summary = _summaryForToast(entity);
    final notif = ref.read(localNotificationServiceProvider);
    if (notif.isForeground) {
      if (summary.isNotEmpty) {
        ref.read(toastControllerProvider).show(summary);
      }
    } else {
      _showLocalNotification(entity, summary, notif);
    }
  }

  Future<void> _showLocalNotification(
    NotificationEntity entity,
    String summary,
    LocalNotificationService notif,
  ) async {
    final title = entity.senderNickname.isEmpty
        ? '瓜呱通知'
        : entity.senderNickname;
    final body = summary.isEmpty ? '收到一条新通知' : summary;
    final route = _routeForNotification(entity);
    final payload = LocalNotificationService.encodePayload({
      'id': entity.id,
      'type': entity.type.name,
      if (route != null) 'route': route,
    });
    await notif.show(id: entity.id, title: title, body: body, payload: payload);
  }

  String? _routeForNotification(NotificationEntity n) {
    switch (n.type) {
      case NotificationType.like:
      case NotificationType.collection:
      case NotificationType.comment:
      case NotificationType.reply:
      case NotificationType.mention:
        return n.postId != null ? '/post/${n.postId}' : null;
      case NotificationType.follow:
        return n.senderUserId.isNotEmpty ? '/user/${n.senderUserId}' : null;
      case NotificationType.unknown:
        return null;
    }
  }

  String _summaryForToast(NotificationEntity n) {
    final nickname = n.senderNickname;
    switch (n.type) {
      case NotificationType.like:
        return '$nickname 赞了你的笔记';
      case NotificationType.collection:
        return '$nickname 收藏了你的笔记';
      case NotificationType.comment:
        return '$nickname 评论了你的笔记';
      case NotificationType.reply:
        return '$nickname 回复了你';
      case NotificationType.follow:
        return '$nickname 关注了你';
      case NotificationType.mention:
        return '$nickname @了你';
      case NotificationType.unknown:
        return '收到一条新通知';
    }
  }

  Future<void> _init() async {
    final repo = ref.read(notificationRepositoryProvider);
    try {
      final count = await repo.unreadCount();
      state = state.copyWith(unreadCount: count);
    } catch (_) {}
    await _loadTab(NotificationTab.all);
  }

  Future<void> switchTab(NotificationTab tab) async {
    if (state.activeTab == tab) return;
    state = state.copyWith(activeTab: tab, clearError: true);
    if (!state.currentTab(tab).initialized) {
      await _loadTab(tab);
    }
  }

  Future<void> ensureLoaded() async {
    final tab = state.activeTab;
    if (!state.currentTab(tab).initialized) {
      await _loadTab(tab);
    }
  }

  Future<void> refresh() async {
    await _loadTab(state.activeTab, force: true);
    try {
      final count = await ref
          .read(notificationRepositoryProvider)
          .unreadCount();
      state = state.copyWith(unreadCount: count);
    } catch (_) {}
  }

  Future<void> loadMore() async {
    final tab = state.activeTab;
    final cur = state.currentTab(tab);
    if (cur.loading || !cur.hasMore) return;
    _updateTab(tab, cur.copyWith(loading: true));
    try {
      final next = cur.page + 1;
      final paged = await ref
          .read(notificationRepositoryProvider)
          .list(tab, page: next);
      _updateTab(
        tab,
        _PagedState(
          list: [...cur.list, ...paged.list],
          page: next,
          hasMore: paged.hasMore,
          initialized: true,
        ),
      );
    } catch (_) {
      _updateTab(tab, state.currentTab(tab).copyWith(loading: false));
    }
  }

  Future<void> markRead(int id) async {
    final prev = state;
    final tab = state.activeTab;
    final cur = state.currentTab(tab);
    final target = cur.list.where((e) => e.id == id).firstOrNull;
    if (target == null || target.isRead) return;
    _updateTab(
      tab,
      cur.copyWith(
        list: cur.list
            .map((e) => e.id == id ? e.copyWith(isRead: true) : e)
            .toList(),
      ),
    );
    if (tab != NotificationTab.all) {
      final allList = state.all.list
          .map((e) => e.id == id ? e.copyWith(isRead: true) : e)
          .toList();
      state = state.copyWith(all: state.all.copyWith(list: allList));
    }
    state = state.copyWith(
      unreadCount: (state.unreadCount > 0 ? state.unreadCount - 1 : 0),
    );
    try {
      await ref.read(notificationRepositoryProvider).markRead(id);
    } catch (_) {
      state = prev;
      ref.read(toastControllerProvider).error('操作失败，请重试');
    }
  }

  Future<void> markAllRead() async {
    final prev = state;
    state = state.copyWith(
      all: _markAllReadInTab(state.all),
      like: _markAllReadInTab(state.like),
      comment: _markAllReadInTab(state.comment),
      follow: _markAllReadInTab(state.follow),
      unreadCount: 0,
    );
    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
      ref.read(toastControllerProvider).success('已全部标记为已读');
    } catch (_) {
      state = prev;
      ref.read(toastControllerProvider).error('操作失败，请重试');
    }
  }

  _PagedState _markAllReadInTab(_PagedState s) {
    return s.copyWith(
      list: s.list.map((e) => e.copyWith(isRead: true)).toList(),
    );
  }

  Future<void> _loadTab(NotificationTab tab, {bool force = false}) async {
    if (!force && state.currentTab(tab).initialized) return;
    _updateTab(tab, const _PagedState().copyWith(loading: true));
    state = state.copyWith(loading: true, clearError: true);
    try {
      final paged = await ref.read(notificationRepositoryProvider).list(tab);
      _updateTab(
        tab,
        _PagedState(
          list: paged.list,
          hasMore: paged.hasMore,
          initialized: true,
        ),
      );
    } catch (e) {
      state = state.copyWith(error: e);
      _updateTab(tab, const _PagedState().copyWith(initialized: true));
    } finally {
      state = state.copyWith(loading: false);
    }
  }

  void _updateTab(NotificationTab tab, _PagedState next) {
    switch (tab) {
      case NotificationTab.all:
        state = state.copyWith(all: next);
        break;
      case NotificationTab.like:
        state = state.copyWith(like: next);
        break;
      case NotificationTab.comment:
        state = state.copyWith(comment: next);
        break;
      case NotificationTab.follow:
        state = state.copyWith(follow: next);
        break;
    }
  }
}

final notificationControllerProvider =
    NotifierProvider<NotificationController, NotificationState>(
      NotificationController.new,
    );

final unreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificationControllerProvider).unreadCount;
});
