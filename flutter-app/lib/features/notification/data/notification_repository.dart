import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_data.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/notification_entity.dart';
import 'notification_api.dart';

class NotificationRepository {
  const NotificationRepository(this._api);

  final NotificationApi _api;

  Future<PagedData<NotificationEntity>> list(
    NotificationTab tab, {
    int page = 1,
    int limit = 20,
  }) async {
    final paged = await _api.list(tab, page: page, limit: limit);
    return PagedData<NotificationEntity>(
      list: paged.list.map((e) => e.toEntity()).toList(),
      total: paged.total,
      page: paged.page,
      limit: paged.limit,
      hasMore: paged.hasMore,
    );
  }

  Future<int> unreadCount() => _api.unreadCount();
  Future<void> markRead(int id) => _api.markRead(id);
  Future<void> markAllRead() => _api.markAllRead();
}

final notificationApiProvider = Provider<NotificationApi>(
  (ref) => NotificationApi(ref.watch(dioClientProvider)),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(notificationApiProvider)),
);
