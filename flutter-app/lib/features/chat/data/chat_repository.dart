import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_data.dart';
import '../../../shared/providers/core_providers.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/chat_entity.dart';
import 'chat_api.dart';
import 'chat_dto.dart';

/// 平台客服固定用户 ID
const int kPlatformSupportUserId = 0;

class ChatRepository {
  ChatRepository({required ChatApi api, required int? currentUserId})
    : _api = api,
      _currentUserId = currentUserId;

  final ChatApi _api;
  final int? _currentUserId;

  Future<List<ChatSessionEntity>> sessions() async {
    final list = await _api.sessions();
    return list.map((e) => e.toEntity()).toList();
  }

  Future<PagedData<ChatMessageEntity>> messages(
    int sessionId, {
    int page = 1,
    int limit = 20,
    int? before,
  }) async {
    final paged = await _api.messages(
      sessionId,
      page: page,
      limit: limit,
      before: before,
    );
    return PagedData<ChatMessageEntity>(
      list: paged.list
          .map((d) => d.toEntity(currentUserId: _currentUserId))
          .toList(),
      total: paged.total,
      page: paged.page,
      limit: paged.limit,
      hasMore: paged.hasMore,
    );
  }

  Future<ChatSessionEntity> createSession({
    required int targetId,
    required String type,
  }) async {
    final dto = await _api.createSession(
      CreateSessionRequest(targetId: targetId, type: type),
    );
    return dto.toEntity();
  }

  Future<ChatSessionEntity> ensurePrivateSession({
    required int targetUserId,
    List<ChatSessionEntity> cached = const [],
  }) async {
    for (final s in cached) {
      if (s.type == 'private' && s.peerId == targetUserId) {
        return s;
      }
    }
    return createSession(targetId: targetUserId, type: 'private');
  }

  Future<ChatSessionEntity> createGroup({
    required String name,
    required List<int> memberIds,
  }) async {
    final dto = await _api.createGroup(
      CreateGroupRequest(name: name, memberIds: memberIds),
    );
    return dto.toEntity();
  }

  Future<void> markRead(int sessionId) => _api.markRead(sessionId);

  Future<List<ChatGroupMemberEntity>> groupMembers(int groupId) async {
    final list = await _api.groupMembers(groupId);
    return list.map((e) => e.toEntity()).toList();
  }

  Future<void> recallMessage(int messageId) => _api.recallMessage(messageId);

  ChatMessageEntity parseSocketMessage(Map<String, dynamic> data) {
    return ChatMessageDto.fromSocket(
      data,
    ).toEntity(currentUserId: _currentUserId);
  }
}

final chatApiProvider = Provider<ChatApi>(
  (ref) => ChatApi(ref.watch(dioClientProvider)),
);

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(
    api: ref.watch(chatApiProvider),
    currentUserId: ref.watch(currentUserProvider)?.id,
  );
});
