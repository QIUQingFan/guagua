import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/domain/user_entity.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry.dart';
import '../../../../shared/widgets/loading.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../discover/presentation/widgets/post_card.dart';
import '../../application/user_profile_controller.dart';
import '../../data/user_dto.dart';

/// 个人中心：底部导航"我"Tab。
///
/// 与 [UserProfilePage] 共用 [userProfileProvider]，
/// 但顶部不显示返回按钮，操作区为"编辑资料 / 设置"。
class PersonalCenterPage extends ConsumerStatefulWidget {
  const PersonalCenterPage({super.key});

  @override
  ConsumerState<PersonalCenterPage> createState() => _PersonalCenterPageState();
}

class _PersonalCenterPageState extends ConsumerState<PersonalCenterPage> {
  String? _userId;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return auth.when(
      loading: () => const LoadingSpinner(),
      error: (e, _) => ErrorRetryView(
        message: e.toString(),
        onRetry: () => ref.invalidate(authControllerProvider),
      ),
      data: (entity) {
        if (entity == null) {
          return _GuestView(onLogin: () => context.go('/auth/login'));
        }
        final id = entity.user.userId;
        if (_userId != id) {
          _userId = id;
          Future.microtask(() => ref.invalidate(userProfileProvider(id)));
        }
        return _SelfProfile(userId: id);
      },
    );
  }
}

class _SelfProfile extends ConsumerWidget {
  const _SelfProfile({required this.userId});

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
        data: (state) => _Body(state: state, userId: userId),
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

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(userProfileProvider(widget.userId).notifier).refresh(),
      child: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          SliverAppBar(
            leading: const SizedBox.shrink(),
            actions: [
              IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => context.push('/profile/settings'),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            pinned: false,
            floating: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
          ),
          SliverToBoxAdapter(
            child: _SelfHeader(user: user, stats: stats),
          ),
          SliverToBoxAdapter(
            child: _TabBar(
              activeTab: state.activeTab,
              onSwitch: (tab) => ref
                  .read(userProfileProvider(widget.userId).notifier)
                  .switchTab(tab),
            ),
          ),
          _PostsList(state: state),
        ],
      ),
    );
  }
}

class _SelfHeader extends StatelessWidget {
  const _SelfHeader({required this.user, required this.stats});

  final UserEntity? user;
  final UserStatsEntity? stats;

  @override
  Widget build(BuildContext context) {
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
              Column(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.push('/profile/edit'),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: Text(l.userEditProfile),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/profile/settings'),
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: Text(l.userSettings),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                    ),
                  ),
                ],
              ),
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

class _TabBar extends StatelessWidget {
  const _TabBar({required this.activeTab, required this.onSwitch});

  final UserProfileTab activeTab;
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
          _TabItem(
            label: l.userCollections,
            selected: activeTab == UserProfileTab.collections,
            onTap: () => onSwitch(UserProfileTab.collections),
          ),
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
  const _PostsList({required this.state});

  final UserProfileState state;

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
          message: context.l10n.userMyPostsEmpty,
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

/// 未登录访客视图：引导登录。
class _GuestView extends StatelessWidget {
  const _GuestView({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.toastUnauthorized,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: onLogin,
                child: Text(context.l10n.authLogin),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
