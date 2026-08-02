import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/loading.dart';
import '../../../chat/application/chat_list_controller.dart';

/// 分享笔记到聊天的会话选择器
Future<int?> showSessionPicker(BuildContext context, WidgetRef ref) async {
  return showDialog<int>(
    context: context,
    builder: (_) => const _SessionPickerDialog(),
  );
}

class _SessionPickerDialog extends ConsumerStatefulWidget {
  const _SessionPickerDialog();

  @override
  ConsumerState<_SessionPickerDialog> createState() =>
      _SessionPickerDialogState();
}

class _SessionPickerDialogState extends ConsumerState<_SessionPickerDialog> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(chatListControllerProvider.notifier).refresh(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatListControllerProvider);
    final l = context.l10n;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Text(
                    l.shareSelectSession,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _body(context, state, l)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ChatListState state, AppLocalizations l) {
    if (state.loading && state.sessions.isEmpty) {
      return const LoadingSpinner();
    }
    if (state.sessions.isEmpty) {
      return EmptyState(
        icon: Icons.chat_bubble_outline,
        message: l.shareNoSessions,
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: state.sessions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final s = state.sessions[i];
        return ListTile(
          leading: Avatar(url: s.avatar, size: 40),
          title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            s.lastMessage.isEmpty
                ? (s.isGroup ? l.chatGroupType : l.chatPrivateType)
                : s.lastMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: s.unreadCount > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${s.unreadCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                )
              : null,
          onTap: () => Navigator.pop(context, s.id),
        );
      },
    );
  }
}

Future<void> shareNoteToChat({
  required BuildContext context,
  required WidgetRef ref,
  required int noteId,
  required String title,
  String? coverUrl,
}) async {
  final sessionId = await showSessionPicker(context, ref);
  if (sessionId == null) return;
  if (!context.mounted) return;

  final params = <String, String>{
    'shareId': '$noteId',
    'shareTitle': title,
    if (coverUrl != null && coverUrl.isNotEmpty) 'shareCover': coverUrl,
  };
  final query = params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
  context.push('/chat/$sessionId?$query');
}
