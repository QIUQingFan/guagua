import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry.dart';
import '../../../../shared/widgets/loading.dart';
import '../../application/notification_controller.dart';
import '../../domain/notification_entity.dart';

class NotificationPage extends ConsumerStatefulWidget {
  const NotificationPage({super.key});

  @override
  ConsumerState<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends ConsumerState<NotificationPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _scrollControllers = <int, ScrollController>{};

  static const _tabs = [
    NotificationTab.all,
    NotificationTab.like,
    NotificationTab.comment,
    NotificationTab.follow,
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        ref
            .read(notificationControllerProvider.notifier)
            .switchTab(_tabs[_tabCtrl.index]);
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  ScrollController _scrollCtrlFor(int index) {
    return _scrollControllers.putIfAbsent(index, () {
      final c = ScrollController();
      c.addListener(() {
        if (!c.hasClients) return;
        final pos = c.position;
        if (pos.pixels >= pos.maxScrollExtent - 200) {
          ref.read(notificationControllerProvider.notifier).loadMore();
        }
      });
      return c;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(notificationControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.notificationTitle),
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () => ref
                  .read(notificationControllerProvider.notifier)
                  .markAllRead(),
              child: Text(l.notificationMarkAllRead),
            ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabAlignment: TabAlignment.start,
          isScrollable: true,
          tabs: [
            Tab(text: l.notificationTabAll),
            Tab(text: l.notificationTabLike),
            Tab(text: l.notificationTabComment),
            Tab(text: l.notificationTabFollow),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            _TabView(
              tab: _tabs[i],
              state: state,
              scrollCtrl: _scrollCtrlFor(i),
            ),
        ],
      ),
    );
  }
}

class _TabView extends ConsumerWidget {
  const _TabView({
    required this.tab,
    required this.state,
    required this.scrollCtrl,
  });

  final NotificationTab tab;
  final NotificationState state;
  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = state.currentTab(tab);

    if (cur.loading && cur.list.isEmpty) {
      return const LoadingSpinner();
    }
    if (state.error != null && cur.list.isEmpty) {
      return ErrorRetryView(
        message: state.error.toString(),
        onRetry: () =>
            ref.read(notificationControllerProvider.notifier).switchTab(tab),
      );
    }
    if (cur.list.isEmpty) {
      return EmptyState(
        icon: Icons.notifications_none_outlined,
        message: context.l10n.notificationEmpty,
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(notificationControllerProvider.notifier).refresh(),
      child: ListView.separated(
        controller: scrollCtrl,
        itemCount: cur.list.length + (cur.hasMore ? 1 : 0),
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: Theme.of(context).dividerColor),
        itemBuilder: (ctx, i) {
          if (i >= cur.list.length) {
            Future.microtask(
              () =>
                  ref.read(notificationControllerProvider.notifier).loadMore(),
            );
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final n = cur.list[i];
          return _NotificationItem(
            item: n,
            onTap: () => _onTap(context, ref, n),
          );
        },
      ),
    );
  }

  void _onTap(BuildContext context, WidgetRef ref, NotificationEntity n) {
    if (!n.isRead) {
      ref.read(notificationControllerProvider.notifier).markRead(n.id);
    }
    switch (n.type) {
      case NotificationType.like:
      case NotificationType.collection:
      case NotificationType.comment:
      case NotificationType.reply:
      case NotificationType.mention:
        if (n.postId != null) {
          context.push('/post/${n.postId}');
        }
        break;
      case NotificationType.follow:
      case NotificationType.unknown:
        if (n.senderUserId.isNotEmpty) {
          context.push('/user/${n.senderUserId}');
        }
        break;
    }
  }
}

class _NotificationItem extends StatelessWidget {
  const _NotificationItem({required this.item, required this.onTap});

  final NotificationEntity item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Ink(
        color: item.isRead
            ? Theme.of(context).scaffoldBackgroundColor
            : Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(
                url: item.senderAvatar,
                size: 40,
                verified: item.senderVerified == 1,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.senderNickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AppTextSize.body,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          Formatters.relativeTime(item.createdAt),
                          style: TextStyle(
                            fontSize: AppTextSize.caption,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _summary(context, item),
                      style: TextStyle(
                        fontSize: AppTextSize.caption,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _Trailing(item: item),
            ],
          ),
        ),
      ),
    );
  }

  String _summary(BuildContext context, NotificationEntity n) {
    final l = context.l10n;
    switch (n.type) {
      case NotificationType.like:
        return '${l.notificationTabLike} · ${n.postTitle}';
      case NotificationType.collection:
        return '${l.userCollections} · ${n.postTitle}';
      case NotificationType.comment:
        return n.commentContent.isEmpty
            ? l.notificationTabComment
            : '${l.notificationTabComment}: ${n.commentContent}';
      case NotificationType.reply:
        return n.commentContent.isEmpty
            ? l.notificationTabComment
            : '回复了你: ${n.commentContent}';
      case NotificationType.follow:
        return l.notificationTabFollow;
      case NotificationType.mention:
        return l.notificationTabMention;
      case NotificationType.unknown:
        return '';
    }
  }
}

class _Trailing extends StatelessWidget {
  const _Trailing({required this.item});

  final NotificationEntity item;

  @override
  Widget build(BuildContext context) {
    if (item.postImage.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.image),
        child: CachedNetworkImage(
          imageUrl: item.postImage,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          memCacheWidth: 88,
          placeholder: (_, __) => Container(
            width: 44,
            height: 44,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          errorWidget: (_, __, ___) => Container(
            width: 44,
            height: 44,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      );
    }
    if (item.type == NotificationType.follow) {
      return OutlinedButton(
        onPressed: () {
          if (item.senderUserId.isNotEmpty) {
            context.push('/user/${item.senderUserId}');
          }
        },
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          textStyle: const TextStyle(fontSize: AppTextSize.caption),
        ),
        child: Text(context.l10n.userSendMessage),
      );
    }
    if (!item.isRead) {
      return Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: AppSpacing.sm),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
      );
    }
    return const SizedBox(width: 8);
  }
}
