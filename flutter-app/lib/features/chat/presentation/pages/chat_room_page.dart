import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../application/chat_list_controller.dart';
import '../../application/chat_room_controller.dart';
import '../../domain/chat_entity.dart';
import '../widgets/chat_image_sender.dart';

/// 聊天窗口
class ChatRoomPage extends ConsumerStatefulWidget {
  const ChatRoomPage({super.key, required this.sessionId});

  final int sessionId;

  @override
  ConsumerState<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends ConsumerState<ChatRoomPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _canSend = false;
  bool _shareHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleShareIfNeeded();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleShareIfNeeded() {
    if (_shareHandled) return;
    final goState = GoRouterState.of(context);
    final shareId = int.tryParse(goState.uri.queryParameters['shareId'] ?? '');
    if (shareId == null || shareId <= 0) return;
    _shareHandled = true;
    final shareTitle = goState.uri.queryParameters['shareTitle'] ?? '';
    final shareCover = goState.uri.queryParameters['shareCover'];

    Future.microtask(() async {
      await ref
          .read(chatRoomControllerProvider(widget.sessionId).notifier)
          .sendText(
            widget.sessionId,
            content: shareTitle,
            type: ChatMessageType.shareCard,
            shareId: shareId,
            shareTitle: shareTitle,
            shareCover: shareCover,
          );
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    setState(() => _canSend = false);
    await ref
        .read(chatRoomControllerProvider(widget.sessionId).notifier)
        .sendText(widget.sessionId, content: text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatRoomControllerProvider(widget.sessionId));
    final l = context.l10n;
    final session = _findSession(ref);

    _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            if (session != null) Avatar(url: session.avatar, size: 32),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session?.name ?? l.chatSessionTitle,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    _connectionLabel(state.connected, l),
                    style: TextStyle(
                      fontSize: 11,
                      color: state.connected ? AppColors.online : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _messageList(context, ref, state, l)),
            if (state.replyTarget != null)
              _buildReplyBar(context, ref, state, l),
            _buildInputBar(context, l),
          ],
        ),
      ),
    );
  }

  Widget _messageList(
    BuildContext context,
    WidgetRef ref,
    ChatRoomState state,
    AppLocalizations l,
  ) {
    if (state.loading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.chatHistoryLoadFailed),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: () => ref
                  .read(chatRoomControllerProvider(widget.sessionId).notifier)
                  .loadInitial(widget.sessionId),
              child: Text(l.commonRetry),
            ),
          ],
        ),
      );
    }
    if (state.messages.isEmpty) {
      return Center(child: Text(l.chatMessageEmpty));
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      itemCount: state.messages.length + (state.hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == 0 && state.hasMore) {
          Future.microtask(
            () => ref
                .read(chatRoomControllerProvider(widget.sessionId).notifier)
                .loadMore(widget.sessionId),
          );
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final index = state.hasMore ? i - 1 : i;
        final msg = state.messages[index];
        return _MessageBubble(
          message: msg,
          onLongPress: () => _showMessageMenu(context, ref, msg, l),
        );
      },
    );
  }

  Widget _buildReplyBar(
    BuildContext context,
    WidgetRef ref,
    ChatRoomState state,
    AppLocalizations l,
  ) {
    final target = state.replyTarget!;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      color: colors.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(Icons.reply, size: 16, color: colors.outline),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              l.chatReplyTo(
                target.fromNickname.isEmpty ? '?' : target.fromNickname,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
          ),
          GestureDetector(
            onTap: () => ref
                .read(chatRoomControllerProvider(widget.sessionId).notifier)
                .setReply(null),
            child: Icon(Icons.close, size: 16, color: colors.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context, AppLocalizations l) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _showAttachMenu(context),
          ),
          Expanded(
            child: TextField(
              controller: _inputController,
              minLines: 1,
              maxLines: 4,
              onChanged: (v) => setState(() => _canSend = v.trim().isNotEmpty),
              decoration: InputDecoration(
                hintText: l.chatInputPlaceholder,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colors.surfaceContainerHighest,
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton.filled(
            onPressed: _canSend ? _send : null,
            icon: const Icon(Icons.send, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: colors.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }

  void _showMessageMenu(
    BuildContext context,
    WidgetRef ref,
    ChatMessageEntity msg,
    AppLocalizations l,
  ) {
    final controller = ref.read(
      chatRoomControllerProvider(widget.sessionId).notifier,
    );
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: Text(l.chatReply),
              onTap: () {
                Navigator.pop(ctx);
                controller.setReply(msg);
              },
            ),
            if (msg.isMine && msg.status != MessageStatus.recalled)
              ListTile(
                leading: const Icon(Icons.undo),
                title: Text(l.chatRecall),
                onTap: () async {
                  Navigator.pop(ctx);
                  final age = msg.createdAt != null
                      ? DateTime.now().difference(msg.createdAt!)
                      : Duration.zero;
                  if (age.inSeconds > 120) {
                    ref
                        .read(toastControllerProvider)
                        .error(l.chatRecallTimeout);
                    return;
                  }
                  try {
                    await controller.recall(widget.sessionId, msg);
                  } catch (_) {
                    ref.read(toastControllerProvider).error(l.chatRecallFailed);
                  }
                },
              ),
            if (msg.status == MessageStatus.failed)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(l.chatResend),
                onTap: () {
                  Navigator.pop(ctx);
                  controller.resend(widget.sessionId, msg);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showAttachMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(context.l10n.chatSendImage),
              onTap: () {
                Navigator.pop(ctx);
                _sendImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(context.l10n.chatShareCard),
              onTap: () {
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendImage() async {
    final url = await pickAndUploadChatImage(context, ref);
    if (url == null) return;
    await ref
        .read(chatRoomControllerProvider(widget.sessionId).notifier)
        .sendText(widget.sessionId, content: url, type: ChatMessageType.image);
    _scrollToBottom();
  }

  ChatSessionEntity? _findSession(WidgetRef ref) {
    final list = ref.watch(chatListControllerProvider).sessions;
    for (final s in list) {
      if (s.id == widget.sessionId) return s;
    }
    return null;
  }

  String _connectionLabel(bool connected, AppLocalizations l) {
    if (connected) return l.chatConnected;
    return l.chatConnecting;
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onLongPress});

  final ChatMessageEntity message;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    if (message.type == ChatMessageType.system ||
        message.status == MessageStatus.recalled) {
      return _systemOrRecall(context);
    }
    return _bubble(context);
  }

  void _goToSharePost(BuildContext context) {
    final id = message.shareId;
    if (id == null || id <= 0) return;
    context.push('/post/$id');
  }

  Widget _systemOrRecall(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Text(
            message.status == MessageStatus.recalled
                ? (message.isMine
                      ? context.l10n.chatRecallSelf
                      : context.l10n.chatRecalled(
                          message.fromNickname.isEmpty
                              ? '?'
                              : message.fromNickname,
                        ))
                : message.content,
            style: TextStyle(fontSize: 12, color: colors.outline),
          ),
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isMine = message.isMine;
    final bg = isMine ? AppColors.primary : colors.surfaceContainerHighest;
    final fg = isMine ? Colors.white : colors.onSurface;

    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisAlignment: isMine
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine) ...[
              Avatar(url: message.fromAvatar, size: 36),
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: isMine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isMine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2, left: 4),
                      child: Text(
                        message.fromNickname,
                        style: TextStyle(fontSize: 11, color: colors.outline),
                      ),
                    ),
                  if (message.replyTo != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: 0.6,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.image),
                      ),
                      child: Text(
                        message.replyToContent ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: colors.outline),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(AppRadius.card),
                        topRight: const Radius.circular(AppRadius.card),
                        bottomLeft: isMine
                            ? const Radius.circular(AppRadius.card)
                            : Radius.zero,
                        bottomRight: isMine
                            ? Radius.zero
                            : const Radius.circular(AppRadius.card),
                      ),
                    ),
                    child: _contentWidget(context, fg),
                  ),
                  if (message.status == MessageStatus.failed)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 12,
                            color: Colors.red.shade400,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            context.l10n.chatSendFailed,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.red.shade400,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (message.status == MessageStatus.pending)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 4),
                      child: SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: colors.outline,
                        ),
                      ),
                    )
                  else ...[
                    if (isMine && message.type != ChatMessageType.system)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 4),
                        child: Text(
                          message.readByPeer
                              ? context.l10n.chatMessageRead
                              : context.l10n.chatMessageUnread,
                          style: TextStyle(
                            fontSize: 10,
                            color: message.readByPeer
                                ? colors.outline
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    if (message.createdAt != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 2,
                          right: 4,
                          left: 4,
                        ),
                        child: Text(
                          Formatters.dateTime(message.createdAt),
                          style: TextStyle(fontSize: 10, color: colors.outline),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            if (isMine) const SizedBox(width: AppSpacing.xs),
            if (isMine) Avatar(url: message.fromAvatar, size: 36),
          ],
        ),
      ),
    );
  }

  Widget _contentWidget(BuildContext context, Color fg) {
    if (message.type == ChatMessageType.image) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.image),
          child: Image.network(
            getFullImageUrl(message.content),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(
              height: 80,
              child: Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      );
    }
    if (message.type == ChatMessageType.shareCard) {
      return GestureDetector(
        onTap: () => _goToSharePost(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.shareCover != null && message.shareCover!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.image),
                child: Image.network(
                  message.shareCover!,
                  width: 160,
                  height: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.note_outlined, size: 14, color: fg),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    message.shareTitle?.isNotEmpty == true
                        ? message.shareTitle!
                        : message.content,
                    style: TextStyle(fontSize: 13, color: fg),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Text(message.content, style: TextStyle(fontSize: 15, color: fg));
  }
}
