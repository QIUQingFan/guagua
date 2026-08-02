import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/domain/comment_entity.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../application/comment_list_controller.dart';
import 'comment_input_sheet.dart';

/// 评论列表
class CommentSection extends ConsumerWidget {
  const CommentSection({super.key, required this.postId});

  final int postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(commentListProvider(postId));
    if (state.loading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    if (state.hasError && state.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyState(
          icon: Icons.error_outline,
          message: context.l10n.commonError,
          actionLabel: context.l10n.commonRetry,
          onAction: () =>
              ref.read(commentListProvider(postId).notifier).refresh(postId),
        ),
      );
    }
    if (state.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            '还没有评论，快来抢沙发~',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: AppTextSize.caption,
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((ctx, i) {
        if (i >= state.list.length) {
          if (state.hasMore) {
            Future.microtask(
              () => ref
                  .read(commentListProvider(postId).notifier)
                  .loadMore(postId),
            );
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: Text(
                context.l10n.commonNoMore,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ),
          );
        }
        return _CommentItem(comment: state.list[i], postId: postId);
      }, childCount: state.list.length + 1),
    );
  }
}

class _CommentItem extends ConsumerStatefulWidget {
  const _CommentItem({required this.comment, required this.postId});

  final CommentEntity comment;
  final int postId;

  @override
  ConsumerState<_CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends ConsumerState<_CommentItem> {
  bool _expanded = false;

  CommentEntity get comment => widget.comment;

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(commentListProvider(widget.postId).notifier);
    ref.watch(commentListProvider(widget.postId));
    final replies = controller.repliesOf(comment.id);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(
            url: comment.authorAvatar,
            size: 36,
            verified: comment.authorVerified,
            onTap: () => _goToUser(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _goToUser(context),
                        child: Text(
                          comment.authorNickname,
                          style: TextStyle(
                            fontSize: AppTextSize.caption,
                            color: Theme.of(context).colorScheme.outline,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      Formatters.relativeTime(comment.createdAt),
                      style: TextStyle(
                        fontSize: AppTextSize.micro,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.plainContent,
                  style: const TextStyle(
                    fontSize: AppTextSize.body,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _reply(context),
                      child: Text(
                        context.l10n.postComment,
                        style: TextStyle(
                          fontSize: AppTextSize.micro,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                    if (comment.replyCount > 0) ...[
                      const SizedBox(width: AppSpacing.md),
                      GestureDetector(
                        onTap: _toggleExpand,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.l10n.postExpandReplies(
                                comment.replyCount,
                              ),
                              style: TextStyle(
                                fontSize: AppTextSize.micro,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              _expanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 14,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (_expanded) _buildReplies(context, replies),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          GestureDetector(
            onTap: () => ref
                .read(commentListProvider(widget.postId).notifier)
                .toggleLike(comment.id),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  comment.liked ? Icons.favorite : Icons.favorite_border,
                  size: 16,
                  color: comment.liked
                      ? AppColors.like
                      : Theme.of(context).colorScheme.outline,
                ),
                if (comment.likeCount > 0)
                  Text(
                    Formatters.count(comment.likeCount),
                    style: TextStyle(
                      fontSize: AppTextSize.micro,
                      color: comment.liked
                          ? AppColors.like
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplies(BuildContext context, List<CommentEntity> replies) {
    if (replies.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Text(
          context.l10n.commonNoMore,
          style: TextStyle(
            fontSize: AppTextSize.micro,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in replies) ...[
              _ReplyItem(reply: r),
              if (r != replies.last) const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleExpand() async {
    final controller = ref.read(commentListProvider(widget.postId).notifier);
    if (!_expanded) {
      if (!controller.repliesLoaded(comment.id)) {
        await controller.loadReplies(comment.id);
      }
    }
    if (!mounted) return;
    setState(() => _expanded = !_expanded);
  }

  void _goToUser(BuildContext context) {
    final id = comment.authorUserId;
    if (id.isEmpty) return;
    context.push('/user/$id');
  }

  void _reply(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CommentInputSheet(
        postId: widget.postId,
        parentId: comment.id,
        replyTo: comment.authorNickname,
      ),
    );
  }
}

class _ReplyItem extends StatelessWidget {
  const _ReplyItem({required this.reply});

  final CommentEntity reply;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Avatar(
          url: reply.authorAvatar,
          size: 28,
          verified: reply.authorVerified,
          onTap: () => _goToUser(context),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _goToUser(context),
                child: Text(
                  reply.authorNickname,
                  style: TextStyle(
                    fontSize: AppTextSize.micro,
                    color: Theme.of(context).colorScheme.outline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                reply.plainContent,
                style: const TextStyle(
                  fontSize: AppTextSize.caption,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        Text(
          Formatters.relativeTime(reply.createdAt),
          style: TextStyle(
            fontSize: AppTextSize.micro,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }

  void _goToUser(BuildContext context) {
    final id = reply.authorUserId;
    if (id.isEmpty) return;
    context.push('/user/$id');
  }
}
