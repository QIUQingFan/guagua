import '../../../core/constants/api_paths.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/paged_data.dart';
import '../domain/notification_entity.dart';
import 'notification_dto.dart';

class NotificationApi {
  const NotificationApi(this._client);

  final DioClient _client;

  Future<PagedData<NotificationDto>> list(
    NotificationTab tab, {
    int page = 1,
    int limit = 20,
  }) {
    return _client.getPaged(
      tab.path,
      query: {'page': page, 'limit': limit},
      listKey: 'notifications',
      decode: NotificationDto.fromJson,
    );
  }

  Future<int> unreadCount() async {
    final map = await _client.get(
      ApiPaths.notificationsUnreadCount,
      decode: (d) => d as Map<String, dynamic>,
    );
    return (map['unread_count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(int id) =>
      _client.putVoid(ApiPaths.notificationRead(id));

  Future<void> markAllRead() => _client.putVoid(ApiPaths.notificationsReadAll);
}
