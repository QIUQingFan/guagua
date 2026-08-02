import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/domain/user_entity.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry.dart';
import '../../../../shared/widgets/follow_button.dart';
import '../../../../shared/widgets/loading.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../discover/presentation/widgets/post_card.dart';
import '../../application/follow_controller.dart';
import '../../application/user_profile_controller.dart';
import '../../data/user_dto.dart';

/// 用户主页：查看任意用户资料 + 笔记 / 收藏 Tab。
///
/// [userId] 为瓜呱号字符串（后端 `users.user_id`），与 web 端约定一致。
class UserProfilePage extends ConsumerWidget {
  const UserProfilePage({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userProfileProvider(userId));
    return Scaffold(
      body: async.when(
        loading: () => const LoadingSpinner(),
        error: (e, _) => ErrorRetryView(
          message: e.toString(),
          onRetry: () => ref.invalidate(userProfileProvider(userId)),
        ),
        data: (state) {
          if (state.error != null && state.user == null) {
            return ErrorRetryView(
              message: state.error.toString(),
              onRetry: () =>
                  ref.read(userProfileProvider(userId).notifier).refresh(),
            );
          }
          return _Body(state: state, userId: userId);
        },
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.state, required this.userId});

  final UserProfileState state;
  final String userId;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      Future.microtask(
        () => ref.read(userProfileProvider(widget.userId).notifier).loadMore(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final user = state.user;
    final stats = state.stats;
    final currentUserUserId = ref.watch(currentUserProvider)?.userId;
    final isSelf = user != null && currentUserUserId == user.userId;

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(userProfileProvider(widget.userId).notifier).refresh(),
      child: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          SliverAppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_horiz),
                onPressed: () => _showMoreMenu(context),
              ),
            ],
            pinned: false,
            floating: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
          ),
          SliverToBoxAdapter(
            child: _ProfileHeader(user: user, stats: stats, isSelf: isSelf),
          ),
          SliverToBoxAdapter(
            child: _TabBar(
              activeTab: state.activeTab,
              isSelf: isSelf,
              onSwitch: (tab) => ref
                  .read(userProfileProvider(widget.userId).notifier)
                  .switchTab(tab),
            ),
          ),
          _PostsList(state: state, isSelf: isSelf),
        ],
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(context.l10n.userShareProfile),
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(toastControllerProvider)
                    .success(context.l10n.postLinkCopied);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({
    required this.user,
    required this.stats,
    required this.isSelf,
  });

  final UserEntity? user;
  final UserStatsEntity? stats;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (user == null) return const SizedBox.shrink();
    final u = user!;
    final s = stats;
    final likesAndCollects =
        (s?.likesCount ?? u.likeCount) + (s?.collectionsCount ?? 0);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(url: u.avatar, size: 72, verified: u.isVerified),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTextSize.titleLarge,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '瓜呱号: ${u.userId}',
                      style: TextStyle(
                        fontSize: AppTextSize.caption,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'IP属地: ${u.location.isNotEmpty ? u.location : '未知'}',
                      style: TextStyle(
                        fontSize: AppTextSize.caption,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              _ActionButtons(user: u, isSelf: isSelf),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            u.bio.isNotEmpty ? u.bio : '用户没有任何简介',
            style: TextStyle(
              fontSize: AppTextSize.body,
              color: u.bio.isNotEmpty
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
          if (_PersonalityTags.visibleTags(u).isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _PersonalityTags(user: u),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _StatItem(
                label: l.userStatsFollowing,
                value: s?.followingCount ?? u.followCount,
              ),
              const SizedBox(width: AppSpacing.xl),
              _StatItem(
                label: l.userStatsFollowers,
                value: s?.followersCount ?? u.fansCount,
              ),
              const SizedBox(width: AppSpacing.xl),
              _StatItem(label: '获赞与收藏', value: likesAndCollects),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.user, required this.isSelf});

  final UserEntity user;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isSelf) {
      return OutlinedButton.icon(
        onPressed: () => context.push('/profile/edit'),
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: Text(context.l10n.userEditProfile),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
      );
    }

    final followState = ref.watch(
      followControllerProvider((user.userId, false)),
    );
    return FollowButton(
      isFollowing: followState.following,
      loading: followState.loading,
      onTap: () => ref
          .read(followControllerProvider((user.userId, false)).notifier)
          .toggle(),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          Formatters.count(value),
          style: const TextStyle(
            fontSize: AppTextSize.title,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: AppTextSize.caption,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

/// 个性标签：星座 / MBTI / 学历 / 专业 / 兴趣（对齐 web 端 UserPersonalityTags）。
///
/// 第一个标签前会显示性别图标（男/女），与 web 端一致。
class _PersonalityTags extends StatelessWidget {
  const _PersonalityTags({required this.user});

  final UserEntity user;

  /// 收集可见标签（顺序与 web 端一致）：星座 → MBTI → 学历 → 专业 → 兴趣。
  static List<String> visibleTags(UserEntity u) {
    final tags = <String>[];
    void add(String? s) {
      final t = s?.trim() ?? '';
      if (t.isNotEmpty) tags.add(t);
    }

    add(u.zodiacSign);
    add(u.mbti);
    add(u.education);
    add(u.major);
    for (final interest in u.interests) {
      add(interest);
    }
    return tags;
  }

  @override
  Widget build(BuildContext context) {
    final tags = visibleTags(user);
    if (tags.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chipBg = isDark ? AppColors.surfaceDark : AppColors.backgroundLight;
    final chipFg = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    final chipBorder = isDark ? AppColors.dividerDark : AppColors.dividerLight;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (var i = 0; i < tags.length; i++)
          _Tag(
            text: tags[i],
            backgroundColor: chipBg,
            foregroundColor: chipFg,
            borderColor: chipBorder,
            leading: i == 0 ? _genderIcon(user.genderText, chipFg) : null,
          ),
      ],
    );
  }

  Widget? _genderIcon(String gender, Color color) {
    if (gender == '男') {
      return Icon(Icons.male, size: 14, color: color);
    }
    if (gender == '女') {
      return Icon(Icons.female, size: 14, color: color);
    }
    return null;
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.text,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    this.leading,
  });

  final String text;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          Text(
            text,
            style: TextStyle(
              fontSize: AppTextSize.caption,
              color: foregroundColor,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.activeTab,
    required this.isSelf,
    required this.onSwitch,
  });

  final UserProfileTab activeTab;
  final bool isSelf;
  final ValueChanged<UserProfileTab> onSwitch;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _TabItem(
            label: l.userPosts,
            selected: activeTab == UserProfileTab.posts,
            onTap: () => onSwitch(UserProfileTab.posts),
          ),
          if (isSelf)
            _TabItem(
              label: l.userCollections,
              selected: activeTab == UserProfileTab.collections,
              onTap: () => onSwitch(UserProfileTab.collections),
            ),
          if (isSelf)
            _TabItem(
              label: l.userLikes,
              selected: activeTab == UserProfileTab.likes,
              onTap: () => onSwitch(UserProfileTab.likes),
            ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppTextSize.body,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected
                  ? AppColors.primary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _PostsList extends StatelessWidget {
  const _PostsList({required this.state, required this.isSelf});

  final UserProfileState state;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final paged = switch (state.activeTab) {
      UserProfileTab.posts => state.posts,
      UserProfileTab.collections => state.collections,
      UserProfileTab.likes => state.likes,
    };
    final list = paged.list;
    final hasMore = paged.hasMore;
    final loading = paged.loading;

    if (list.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.note_outlined,
          message: isSelf
              ? context.l10n.userMyPostsEmpty
              : context.l10n.userPostsEmpty,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childCount: list.length + (hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i >= list.length) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        context.l10n.commonNoMore,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
            );
          }
          return PostCard(post: list[i]);
        },
      ),
    );
  }
}
