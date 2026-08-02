import '../../../core/constants/api_paths.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/paged_data.dart';
import 'chat_dto.dart';

class ChatApi {
  const ChatApi(this._client);

  final DioClient _client;

  Future<List<ChatSessionDto>> sessions() async {
    final raw = await _client.get(ApiPaths.chatSessions, decode: (d) => d);
    final list = raw is List
        ? raw
        : (raw is Map
              ? raw['sessions'] ?? raw['list'] ?? const <dynamic>[]
              : const <dynamic>[]);
    return (list as List<dynamic>)
        .map((e) => ChatSessionDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PagedData<ChatMessageDto>> messages(
    int sessionId, {
    int page = 1,
    int limit = 20,
    int? before,
  }) {
    return _client.getPaged(
      ApiPaths.chatMessages(sessionId),
      query: {
        'page': page,
        'limit': limit,
        if (before != null) 'before': before,
      },
      listKey: 'messages',
      decode: ChatMessageDto.fromJson,
    );
  }

  Future<ChatSessionDto> createSession(CreateSessionRequest req) {
    return _client.post(
      ApiPaths.chatSessions,
      data: req.toJson(),
      decode: (d) => ChatSessionDto.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<void> markRead(int sessionId) =>
      _client.postVoid(ApiPaths.chatSessionRead(sessionId));

  Future<ChatSessionDto> createGroup(CreateGroupRequest req) {
    return _client.post(
      ApiPaths.chatGroups,
      data: req.toJson(),
      decode: (d) => ChatSessionDto.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<List<ChatGroupMemberDto>> groupMembers(int groupId) async {
    final raw = await _client.get(
      ApiPaths.chatGroupMembers(groupId),
      decode: (d) => d,
    );
    final list = raw is List
        ? raw
        : (raw is Map
              ? raw['members'] ?? const <dynamic>[]
              : const <dynamic>[]);
    return (list as List<dynamic>)
        .map((e) => ChatGroupMemberDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> recallMessage(int messageId) =>
      _client.postVoid(ApiPaths.chatMessageRecall(messageId));
}
