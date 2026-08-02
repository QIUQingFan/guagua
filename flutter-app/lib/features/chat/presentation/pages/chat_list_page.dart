import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry.dart';
import '../../../notification/application/notification_controller.dart';
import '../../application/chat_list_controller.dart';
import '../../data/chat_repository.dart';
import '../../domain/chat_entity.dart';

class ChatListPage extends ConsumerWidget {
  const ChatListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatListControllerProvider);
    final l = context.l10n;
    final notificationUnread = ref.watch(unreadCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.chatTitle),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: notificationUnread > 0,
              label: Text(
                notificationUnread > 99 ? '99+' : '$notificationUnread',
              ),
              child: const Icon(Icons.notifications_none_outlined),
            ),
            tooltip: l.notificationTitle,
            onPressed: () => context.push('/notifications'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.edit_square),
            onSelected: (value) {
              if (value == 'private') {
                _createSession(context, ref);
              } else if (value == 'group') {
                _createGroup(context, ref);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'private',
                child: Row(
                  children: [
                    const Icon(Icons.person_add_outlined, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Text(l.chatNewSession),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'group',
                child: Row(
                  children: [
                    const Icon(Icons.group_add_outlined, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    const Text('创建群聊'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(child: _body(context, ref, state, l)),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    ChatListState state,
    AppLocalizations l,
  ) {
    if (state.loading && state.sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.sessions.isEmpty) {
      return ErrorRetryView(
        message: l.commonNetworkError,
        onRetry: () => ref.read(chatListControllerProvider.notifier).refresh(),
      );
    }
    if (state.isEmpty) {
      return EmptyState(icon: Icons.chat_bubble_outline, message: l.chatEmpty);
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(chatListControllerProvider.notifier).refresh(),
      child: ListView.separated(
        itemCount: state.sessions.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (ctx, i) {
          final session = state.sessions[i];
          return _SessionTile(
            session: session,
            onTap: () async {
              await ref
                  .read(chatListControllerProvider.notifier)
                  .clearUnread(session.id);
              if (!ctx.mounted) return;
              ctx.push('/chat/${session.id}');
            },
          );
        },
      ),
    );
  }

  Future<void> _createSession(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final controller = TextEditingController();
    final guaguaId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.chatNewSession),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: context.l10n.authUserIdLabel,
            hintText: context.l10n.authUserIdHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(context.l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (guaguaId == null || guaguaId.isEmpty) return;
    if (!context.mounted) return;

    final targetId = await ref
        .read(chatListControllerProvider.notifier)
        .findUserIdByGuaguaId(guaguaId);
    if (targetId == null) {
      if (context.mounted) {
        ref.read(toastControllerProvider).error(l.userNotFound);
      }
      return;
    }
    final session = await ref
        .read(chatListControllerProvider.notifier)
        .ensurePrivateSession(targetId);
    if (session == null) {
      if (context.mounted) {
        ref.read(toastControllerProvider).error(l.chatCreateSessionFailed);
      }
      return;
    }
    if (!context.mounted) return;
    await ref.read(chatListControllerProvider.notifier).refresh();
    if (context.mounted) context.push('/chat/${session.id}');
  }

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final nameCtrl = TextEditingController();
    final membersCtrl = TextEditingController();

    final result = await showDialog<({String name, String members})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建群聊'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '群名称',
                hintText: '请输入群名称',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: membersCtrl,
              keyboardType: TextInputType.text,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '群成员瓜呱号',
                hintText: '多个瓜呱号用逗号分隔',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, (
              name: nameCtrl.text.trim(),
              members: membersCtrl.text.trim(),
            )),
            child: Text(l.commonConfirm),
          ),
        ],
      ),
    );

    if (result == null) return;
    final groupName = result.name;
    final membersRaw = result.members;
    if (groupName.isEmpty) {
      if (context.mounted) {
        ref.read(toastControllerProvider).error('请输入群名称');
      }
      return;
    }

    final guaguaIds = membersRaw
        .split(RegExp(r'[,，\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (guaguaIds.isEmpty) {
      if (context.mounted) {
        ref.read(toastControllerProvider).error('请输入至少一个群成员瓜呱号');
      }
      return;
    }

    final List<int> memberIds = [];
    for (final id in guaguaIds) {
      final internalId = await ref
          .read(chatListControllerProvider.notifier)
          .findUserIdByGuaguaId(id);
      if (internalId != null) {
        memberIds.add(internalId);
      }
    }

    if (memberIds.isEmpty) {
      if (context.mounted) {
        ref.read(toastControllerProvider).error(l.userNotFound);
      }
      return;
    }

    try {
      final session = await ref
          .read(chatRepositoryProvider)
          .createGroup(name: groupName, memberIds: memberIds);
      if (!context.mounted) return;
      await ref.read(chatListControllerProvider.notifier).refresh();
      if (context.mounted) context.push('/chat/${session.id}');
    } catch (_) {
      if (context.mounted) {
        ref.read(toastControllerProvider).error('创建群聊失败，请重试');
      }
    }
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.onTap});

  final ChatSessionEntity session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final preview = _buildPreview();

    return ListTile(
      onTap: onTap,
      leading: Avatar(url: session.avatar, size: 48),
      title: Row(
        children: [
          if (session.isGroup)
            Container(
              margin: const EdgeInsets.only(right: AppSpacing.xs),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                context.l10n.chatGroupType,
                style: const TextStyle(fontSize: 10, color: AppColors.primary),
              ),
            ),
          Expanded(
            child: Text(
              session.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.titleMedium,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            Formatters.relativeTime(session.lastMessageTime),
            style: tt.bodySmall?.copyWith(color: colors.outline),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodyMedium?.copyWith(color: colors.outline),
            ),
          ),
          if (session.unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(left: AppSpacing.sm),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                session.unreadCount > 99 ? '99+' : '${session.unreadCount}',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  String _buildPreview() {
    if (session.lastMessage.isEmpty) return '';
    final sender = session.lastMessageSender;
    if (sender.isEmpty) return session.lastMessage;
    return '$sender: ${session.lastMessage}';
  }
}
