import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../application/discover_controller.dart';
import '../../presentation/widgets/channel_bar.dart';
import '../../presentation/widgets/post_card.dart';

class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(discoverFeedProvider);
    final l = context.l10n;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _SearchEntry(l: l),
            const ChannelBar(),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            Expanded(child: _body(context, ref, feed, l)),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    DiscoverFeedState feed,
    AppLocalizations l,
  ) {
    if (feed.loading && feed.list.isEmpty) {
      return const DiscoverSkeleton();
    }
    if (feed.hasError && feed.list.isEmpty) {
      return ErrorRetryView(
        message: l.commonNetworkError,
        onRetry: () => ref.read(discoverFeedProvider.notifier).refresh(),
      );
    }
    if (feed.isEmpty) {
      return EmptyState(
        icon: Icons.explore_outlined,
        message: l.discoverEmpty,
        actionLabel: l.commonRetry,
        onAction: () => ref.read(discoverFeedProvider.notifier).refresh(),
      );
    }

    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: () => ref.read(discoverFeedProvider.notifier).refresh(),
      child: MasonryGridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        padding: const EdgeInsets.all(AppSpacing.sm),
        itemCount: feed.list.length + (feed.hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i >= feed.list.length) {
            Future.microtask(
              () => ref.read(discoverFeedProvider.notifier).loadMore(),
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
          return PostCard(post: feed.list[i]);
        },
      ),
    );
  }
}

/// 首页顶部搜索入口
class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.l});

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => context.push('/search'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 18, color: colors.outline),
            const SizedBox(width: AppSpacing.xs),
            Text(
              l.searchHint,
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: colors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
