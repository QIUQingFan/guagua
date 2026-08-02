import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../../shop/application/shop_controllers.dart';
import '../../../shop/data/shop_repository.dart';
import '../../application/ai_chat_controller.dart';
import '../../domain/ai_entity.dart';

/// AI 购物助手对话
class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key, this.productId});

  final int? productId;

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    if (widget.productId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _inputController.text = '帮我介绍一下这个商品';
          setState(() => _canSend = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
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
    await ref.read(aiChatControllerProvider.notifier).send(text);
    _scrollToBottom();
  }

  Future<void> _quickAsk(String question) async {
    if (ref.read(aiChatControllerProvider).sending) return;
    await ref.read(aiChatControllerProvider.notifier).send(question);
    _scrollToBottom();
  }

  Future<void> _addToCart(int productId) async {
    try {
      await ref.read(cartControllerProvider.notifier).add(productId, 1);
      if (mounted) {
        ref.read(toastControllerProvider).success(context.l10n.aiAddedToCart);
      }
    } catch (_) {
      if (mounted) {
        ref.read(toastControllerProvider).error(context.l10n.aiActionFailed);
      }
    }
  }

  void _viewProduct(int productId) {
    context.push('/shop/product/$productId');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiChatControllerProvider);
    final l = context.l10n;

    _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.aiTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l.aiClearHistory,
            onPressed: state.isEmpty ? null : () => _confirmClear(context, l),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _messageList(context, state, l)),
            if (state.isEmpty) _quickAskBar(context, l),
            _buildInputBar(context, l),
          ],
        ),
      ),
    );
  }

  Widget _messageList(
    BuildContext context,
    AiChatState state,
    AppLocalizations l,
  ) {
    if (state.messages.isEmpty) {
      return _emptyState(context, l);
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      itemCount: state.messages.length,
      itemBuilder: (ctx, i) {
        final msg = state.messages[i];
        return _AiMessageBubble(
          message: msg,
          onAddToCart: _addToCart,
          onViewProduct: _viewProduct,
          onRetry: state.sending
              ? null
              : () => ref.read(aiChatControllerProvider.notifier).retryLast(),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context, AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.smart_toy_outlined,
              size: 36,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l.aiWelcome,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _quickAskBar(BuildContext context, AppLocalizations l) {
    final colors = Theme.of(context).colorScheme;
    final questions = [l.aiQuickAsk1, l.aiQuickAsk2, l.aiQuickAsk3];
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: questions
            .map(
              (q) => GestureDetector(
                onTap: () => _quickAsk(q),
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
                    q,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
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
          Expanded(
            child: TextField(
              controller: _inputController,
              minLines: 1,
              maxLines: 4,
              onChanged: (v) => setState(() => _canSend = v.trim().isNotEmpty),
              decoration: InputDecoration(
                hintText: l.aiInputPlaceholder,
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

  Future<void> _confirmClear(BuildContext context, AppLocalizations l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.aiClearHistory),
        content: Text(l.aiClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(aiChatControllerProvider.notifier).clear();
    }
  }
}

class _AiMessageBubble extends StatelessWidget {
  const _AiMessageBubble({
    required this.message,
    required this.onAddToCart,
    required this.onViewProduct,
    required this.onRetry,
  });

  final AiMessageEntity message;
  final ValueChanged<int> onAddToCart;
  final ValueChanged<int> onViewProduct;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final colors = Theme.of(context).colorScheme;
    final bg = isUser ? AppColors.primary : colors.surfaceContainerHighest;
    final fg = isUser ? Colors.white : colors.onSurface;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: const Icon(
                Icons.smart_toy,
                size: 18,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
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
                      bottomLeft: isUser
                          ? const Radius.circular(AppRadius.card)
                          : Radius.zero,
                      bottomRight: isUser
                          ? Radius.zero
                          : const Radius.circular(AppRadius.card),
                    ),
                  ),
                  child: _content(context, fg),
                ),
                if (message.actions.isNotEmpty) _actions(context, colors),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: AppSpacing.xs),
          if (isUser)
            CircleAvatar(
              radius: 16,
              backgroundColor: colors.surfaceContainerHighest,
              child: Icon(Icons.person, size: 18, color: colors.outline),
            ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, Color fg) {
    final l = context.l10n;
    if (message.isFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.aiUnavailable, style: TextStyle(fontSize: 14, color: fg)),
          const SizedBox(height: AppSpacing.xs),
          if (onRetry != null)
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 14),
              label: Text(l.aiRetry),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                minimumSize: const Size(0, 28),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      );
    }
    if (message.isStreaming && message.content.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: fg.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            l.aiThinking,
            style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.6)),
          ),
        ],
      );
    }
    return Text(
      message.content,
      style: TextStyle(fontSize: 14, color: fg, height: 1.4),
    );
  }

  Widget _actions(BuildContext context, ColorScheme colors) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: message.actions.map((a) => _ActionCard(action: a)).toList(),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action});

  final AiActionEntity action;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.image),
        border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.image),
            child: action.cover != null && action.cover!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: action.cover!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _coverPlaceholder(colors),
                  )
                : _coverPlaceholder(colors),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (action.price != null)
                  Text(
                    '¥${action.price!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Column(
            children: [
              if (action.type == AiActionType.addToCart)
                _TinyFilledButton(
                  onPressed: action.productId != null
                      ? () => _addToCart(context, l)
                      : null,
                  label: l.aiAddToCart,
                )
              else if (action.type == AiActionType.buyNow)
                _TinyFilledButton(
                  onPressed: action.productId != null
                      ? () => _buyNow(context)
                      : null,
                  label: l.aiBuyNow,
                )
              else if (action.type == AiActionType.viewProduct)
                _TinyOutlinedButton(
                  onPressed: action.productId != null
                      ? () => _viewProduct(context)
                      : null,
                  label: l.aiViewProduct,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _coverPlaceholder(ColorScheme colors) {
    return Container(
      width: 48,
      height: 48,
      color: colors.surfaceContainerHighest,
      child: Icon(Icons.inventory_2_outlined, size: 20, color: colors.outline),
    );
  }

  void _addToCart(BuildContext context, AppLocalizations l) {
    if (action.productId == null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final toast = container.read(toastControllerProvider);
    container
        .read(cartControllerProvider.notifier)
        .add(action.productId!, 1)
        .then((_) {
          toast.success(l.aiAddedToCart);
        })
        .catchError((_) {
          toast.error(l.aiActionFailed);
        });
  }

  void _viewProduct(BuildContext context) {
    if (action.productId == null) return;
    context.push('/shop/product/${action.productId}');
  }

  void _buyNow(BuildContext context) {
    if (action.productId == null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    container.read(checkoutControllerProvider.notifier)
      ..setItems([CreateOrderItem(productId: action.productId!, quantity: 1)])
      ..setRemark(null);
    context.push('/shop/checkout');
  }
}

class _TinyFilledButton extends StatelessWidget {
  const _TinyFilledButton({required this.onPressed, required this.label});

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          minimumSize: const Size(0, 28),
          textStyle: const TextStyle(fontSize: 12),
          backgroundColor: AppColors.primary,
        ),
        child: Text(label),
      ),
    );
  }
}

class _TinyOutlinedButton extends StatelessWidget {
  const _TinyOutlinedButton({required this.onPressed, required this.label});

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          minimumSize: const Size(0, 28),
          textStyle: const TextStyle(fontSize: 12),
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
        ),
        child: Text(label),
      ),
    );
  }
}
