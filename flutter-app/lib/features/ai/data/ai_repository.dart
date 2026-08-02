import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_paths.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/ai_entity.dart';

class AiRepository {
  const AiRepository(this._dio);

  final Dio _dio;

  Future<String> chat(
    String message, {
    int? conversationId,
    List<Map<String, String>>? history,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiPaths.aiChat,
      data: {
        'message': message,
        if (conversationId != null) 'conversation_id': conversationId,
        if (history != null && history.isNotEmpty) 'history': history,
      },
    );
    final data = res.data ?? const {};
    return (data['reply'] ?? data['content'] ?? '').toString();
  }

  /// SSE 流式对话
  Stream<AiChunk> chatStream(
    String message, {
    int? conversationId,
    List<Map<String, String>>? history,
    String? context,
  }) async* {
    final response = await _dio.post<ResponseBody>(
      ApiPaths.aiChatStream,
      data: {
        'message': message,
        if (conversationId != null) 'conversation_id': conversationId,
        if (history != null && history.isNotEmpty) 'history': history,
        if (context != null && context.isNotEmpty) 'context': context,
      },
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream, application/json'},
      ),
    );

    final stream = response.data!.stream
        .cast<List<int>>()
        .transform(const Utf8Decoder())
        .transform(const LineSplitter());

    final sseBuffer = StringBuffer();
    var inSseEvent = false;

    await for (final line in stream) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (inSseEvent && sseBuffer.isNotEmpty) {
          final chunk = _parseJsonChunk(sseBuffer.toString());
          if (chunk != null) yield chunk;
          sseBuffer.clear();
        }
        inSseEvent = false;
        continue;
      }

      if (trimmed.startsWith('data:')) {
        inSseEvent = true;
        final payload = trimmed.substring(5).trim();
        if (payload == '[DONE]') {
          inSseEvent = false;
          sseBuffer.clear();
          continue;
        }
        if (sseBuffer.isNotEmpty) sseBuffer.write('\n');
        sseBuffer.write(payload);
        continue;
      }

      if (inSseEvent) {
        sseBuffer.clear();
        inSseEvent = false;
      }
      final chunk = _parseJsonChunk(trimmed);
      if (chunk != null) yield chunk;
    }

    if (sseBuffer.isNotEmpty) {
      final chunk = _parseJsonChunk(sseBuffer.toString());
      if (chunk != null) yield chunk;
    }
  }

  AiChunk? _parseJsonChunk(String payload) {
    if (payload.isEmpty) return null;
    try {
      final json = jsonDecode(payload);
      if (json is Map<String, dynamic>) {
        return AiChunk.fromJson(json);
      }
    } catch (_) {}
    return null;
  }
}

final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepository(ref.watch(dioProvider)),
);
