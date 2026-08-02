import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/shared_prefs_storage.dart';
import '../../../shared/providers/core_providers.dart';
import '../../../shared/providers/toast_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../../shop/data/shop_repository.dart';
import '../data/ai_repository.dart';
import '../domain/ai_entity.dart';

class AiChatState {
  const AiChatState({
    this.messages = const [],
    this.sessionId,
    this.sending = false,
    this.error,
  });

  final List<AiMessageEntity> messages;
  final int? sessionId;
  final bool sending;
  final Object? error;

  bool get isEmpty => messages.isEmpty && !sending;

  AiChatState copyWith({
    List<AiMessageEntity>? messages,
    int? sessionId,
    bool? sending,
    Object? error,
    bool clearError = false,
  }) {
    return AiChatState(
      messages: messages ?? this.messages,
      sessionId: sessionId ?? this.sessionId,
      sending: sending ?? this.sending,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AiChatController extends Notifier<AiChatState> {
  int _nextId = 1;
  StreamSubscription<AiChunk>? _sub;

  @override
  AiChatState build() {
    ref.onDispose(() => _sub?.cancel());
    _restoreHistory();
    return const AiChatState();
  }

  void _restoreHistory() {
    final storage = ref.read(sharedPrefsStorageProvider);
    if (storage == null) return;
    final raw = storage.getAiHistory();
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final messages = list
          .map((e) => AiMessageEntity.fromJson(e as Map<String, dynamic>))
          .where((m) => m.status != AiMessageStatus.streaming)
          .toList();
      if (messages.isEmpty) return;
      final sessionId = storage.getAiSessionId();
      _nextId = messages.map((m) => m.id).fold(1, (a, b) => a > b ? a : b) + 1;
      state = AiChatState(messages: messages, sessionId: sessionId);
    } catch (_) {
      storage.clearAiHistory();
    }
  }

  Future<void> _persistHistory() async {
    final storage = ref.read(sharedPrefsStorageProvider);
    if (storage == null) return;
    final toSave = state.messages
        .where((m) => m.status != AiMessageStatus.streaming)
        .toList();
    const max = SharedPrefsStorage.maxAiMessages;
    final limited = toSave.length > max
        ? toSave.sublist(toSave.length - max)
        : toSave;
    final json = jsonEncode(limited.map((m) => m.toJson()).toList());
    await storage.setAiHistory(json);
    await storage.setAiSessionId(state.sessionId);
  }

  AiRepository get _repo => ref.read(aiRepositoryProvider);

  int get _genId => _nextId++;

  /// 发送用户消息并接收流式回复
  Future<void> send(String text) async {
    final content = text.trim();
    if (content.isEmpty || state.sending) return;

    final userMsg = AiMessageEntity(
      id: _genId,
      role: AiRole.user,
      content: content,
      createdAt: DateTime.now(),
    );

    if (_isOrderQuery(content) && ref.read(currentUserProvider) == null) {
      final promptMsg = AiMessageEntity(
        id: _genId,
        role: AiRole.assistant,
        content: _orderLoginPrompt,
        status: AiMessageStatus.done,
        createdAt: DateTime.now(),
      );
      state = AiChatState(
        messages: [...state.messages, userMsg, promptMsg],
        sessionId: state.sessionId,
      );
      await _persistHistory();
      return;
    }

    final assistantId = _genId;
    final assistantMsg = AiMessageEntity(
      id: assistantId,
      role: AiRole.assistant,
      content: '',
      status: AiMessageStatus.streaming,
      createdAt: DateTime.now(),
    );

    state = AiChatState(
      messages: [...state.messages, userMsg, assistantMsg],
      sessionId: state.sessionId,
      sending: true,
      error: null,
    );

    final context = await _buildOrderContextIfNeeded(content);
    final history = _buildHistory();
    await _runStream(assistantId, content, context: context, history: history);
  }

  List<Map<String, String>> _buildHistory() {
    final list = <Map<String, String>>[];
    for (final m in state.messages) {
      if (m.status == AiMessageStatus.streaming) continue;
      if (m.role == AiRole.user || m.role == AiRole.assistant) {
        list.add({
          'role': m.role == AiRole.user ? 'user' : 'assistant',
          'content': m.content,
        });
      }
    }
    return list;
  }

  /// 订单查询关键词检测
  static final _orderKeywords = [
    '订单',
    '物流',
    '快递',
    '发货',
    '收货',
    '退款',
    '退货',
    '运单',
    '订单号',
    '订单状态',
    '到哪了',
    '什么时候',
    '签收',
    'order',
    'delivery',
    'shipping',
    'refund',
    'logistics',
  ];

  bool _isOrderQuery(String text) {
    final lower = text.toLowerCase();
    return _orderKeywords.any((kw) => lower.contains(kw.toLowerCase()));
  }

  static const _orderLoginPrompt = '查询订单需要先登录哦，请登录后再来问我订单相关问题～';

  Future<String?> _buildOrderContextIfNeeded(String message) async {
    if (!_isOrderQuery(message)) return null;
    try {
      final paged = await ref
          .read(orderRepositoryProvider)
          .list(page: 1, limit: 5);
      if (paged.list.isEmpty) return '用户暂无订单记录';
      final buffer = StringBuffer('用户最近订单（用于回答订单相关问题）：\n');
      for (final o in paged.list) {
        final titles = o.items.map((i) => i.title).join('、');
        buffer
          ..writeln('- 订单号: ${o.orderNo}')
          ..writeln('  状态: ${o.status.value}')
          ..writeln('  商品: $titles')
          ..writeln('  金额: ¥${o.totalAmount.toStringAsFixed(2)}')
          ..writeln('  下单时间: ${o.createdAt.toIso8601String()}');
      }
      return buffer.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _runStream(
    int assistantId,
    String message, {
    String? context,
    List<Map<String, String>>? history,
  }) async {
    await _sub?.cancel();
    final buffer = StringBuffer();
    final actions = <AiActionEntity>[];

    try {
      _sub = _repo
          .chatStream(
            message,
            conversationId: state.sessionId,
            history: history,
            context: context,
          )
          .listen(
            (chunk) {
              if (chunk.delta != null && chunk.delta!.isNotEmpty) {
                buffer.write(chunk.delta);
                _patchAssistant(assistantId, content: buffer.toString());
              }
              if (chunk.action != null && chunk.action!.isValid) {
                actions.add(chunk.action!);
                _patchAssistant(assistantId, actions: [...actions]);
              }
              if (chunk.conversationId != null) {
                state = state.copyWith(sessionId: chunk.conversationId);
              }
              if (chunk.done) {
                _patchAssistant(
                  assistantId,
                  status: AiMessageStatus.done,
                  content: buffer.toString(),
                  actions: actions,
                );
              }
            },
            onError: (Object e) {
              _patchAssistant(assistantId, status: AiMessageStatus.failed);
              state = state.copyWith(sending: false, error: e);
              _persistHistory();
            },
            onDone: () {
              final msg = _findMessage(assistantId);
              if (msg != null && msg.status == AiMessageStatus.streaming) {
                _patchAssistant(
                  assistantId,
                  status: AiMessageStatus.done,
                  content: buffer.toString(),
                  actions: actions,
                );
              }
              state = state.copyWith(sending: false);
              _persistHistory();
            },
            cancelOnError: true,
          );

      await _sub!.asFuture<void>();
    } catch (e) {
      _patchAssistant(assistantId, status: AiMessageStatus.failed);
      state = state.copyWith(sending: false, error: e);
    }
  }

  void _patchAssistant(
    int id, {
    String? content,
    List<AiActionEntity>? actions,
    AiMessageStatus? status,
  }) {
    final messages = state.messages.map((m) {
      if (m.id == id) {
        return m.copyWith(
          content: content ?? m.content,
          actions: actions ?? m.actions,
          status: status ?? m.status,
        );
      }
      return m;
    }).toList();
    state = state.copyWith(messages: messages);
  }

  AiMessageEntity? _findMessage(int id) {
    for (final m in state.messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> retryLast() async {
    if (state.sending) return;
    AiMessageEntity? lastUser;
    for (var i = state.messages.length - 1; i >= 0; i--) {
      if (state.messages[i].role == AiRole.user) {
        lastUser = state.messages[i];
        break;
      }
    }
    if (lastUser == null) return;
    final idx = state.messages.indexOf(lastUser);
    final kept = state.messages.sublist(0, idx + 1);
    state = state.copyWith(messages: kept);

    final assistantId = _genId;
    final assistantMsg = AiMessageEntity(
      id: assistantId,
      role: AiRole.assistant,
      content: '',
      status: AiMessageStatus.streaming,
      createdAt: DateTime.now(),
    );
    state = AiChatState(
      messages: [...state.messages, assistantMsg],
      sessionId: state.sessionId,
      sending: true,
    );
    final context = await _buildOrderContextIfNeeded(lastUser.content);
    await _runStream(assistantId, lastUser.content, context: context);
  }

  void clear() {
    _sub?.cancel();
    _nextId = 1;
    state = const AiChatState(sessionId: null);
    ref.read(sharedPrefsStorageProvider)?.clearAiHistory();
    ref.read(toastControllerProvider).success('');
  }
}

final aiChatControllerProvider =
    NotifierProvider<AiChatController, AiChatState>(AiChatController.new);
