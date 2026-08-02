import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/domain/post_entity.dart';
import '../../../../shared/domain/user_entity.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/error_retry.dart';
import '../../../../shared/widgets/follow_button.dart';
import '../../../../shared/widgets/like_button.dart';
import '../../../../shared/widgets/loading.dart';
import '../../../../shared/widgets/tag_chip.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../discover/presentation/widgets/post_card.dart';
import '../../../user/application/follow_controller.dart';
import '../../application/post_detail_controller.dart';
import '../widgets/comment_input_sheet.dart';
import '../widgets/comment_section.dart';
import '../widgets/share_to_chat_picker.dart';

class PostDetailPage extends ConsumerWidget {
  const PostDetailPage({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(postDetailProvider(id));
    return Scaffold(
      body: detailAsync.when(
        loading: () => const LoadingSpinner(label: '加载中…'),
        error: (e, _) => ErrorRetryView(
          message: e.toString(),
          onRetry: () => ref.invalidate(postDetailProvider(id)),
        ),
        data: (detail) => _DetailBody(detail: detail, postId: id),
      ),
      bottomNavigationBar: detailAsync.maybeWhen(
        data: (detail) => _BottomBar(postId: id, detail: detail),
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.detail, required this.postId});

  final PostDetailEntity detail;
  final int postId;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  int _currentImage = 0;

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final post = detail.post;
    final author = detail.author;
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/discover');
              }
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_horiz),
              onPressed: () => _showMoreMenu(context, ref),
            ),
          ],
          pinned: false,
          floating: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (post.isVideo)
                _VideoView(url: post.videoUrl, cover: post.coverUrl)
              else if (post.imageUrls.isNotEmpty)
                _ImageCarousel(
                  images: post.imageUrls,
                  index: _currentImage,
                  onChanged: (i) => setState(() => _currentImage = i),
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post.title.isNotEmpty)
                      Text(
                        post.title,
                        style: const TextStyle(
                          fontSize: AppTextSize.titleLarge,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (post.content.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        post.content,
                        style: const TextStyle(
                          fontSize: AppTextSize.body,
                          height: 1.6,
                        ),
                      ),
                    ],
                    if (post.tags.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: post.tags
                            .map(
                              (t) => TagChip(
                                label: '#$t',
                                onTap: () {
                                  ref
                                      .read(toastControllerProvider)
                                      .show('搜索标签: $t');
                                },
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        if (post.createdAt != null)
                          Text(
                            Formatters.date(post.createdAt),
                            style: TextStyle(
                              fontSize: AppTextSize.caption,
                              color: colors.outline,
                            ),
                          ),
                        if (author.location.isNotEmpty) ...[
                          if (post.createdAt != null)
                            Text(
                              ' · ',
                              style: TextStyle(
                                fontSize: AppTextSize.caption,
                                color: colors.outline,
                              ),
                            ),
                          Text(
                            author.location,
                            style: TextStyle(
                              fontSize: AppTextSize.caption,
                              color: colors.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: 0.3),
              ),
              _AuthorBar(author: author),
              Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: 0.3),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: Text(
                  l.postRelatedComments(post.commentCount),
                  style: const TextStyle(
                    fontSize: AppTextSize.title,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        CommentSection(postId: widget.postId),
        SliverToBoxAdapter(child: _RelatedPostsSection(postId: widget.postId)),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      ],
    );
  }

  void _showMoreMenu(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.report_outlined),
              title: Text(l.postReport),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(toastControllerProvider).show('举报已提交');
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: Text(l.postCopyLink),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(toastControllerProvider).success(l.postLinkCopied);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageCarousel extends StatelessWidget {
  const _ImageCarousel({
    required this.images,
    required this.index,
    required this.onChanged,
  });

  final List<String> images;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: PageView.builder(
            itemCount: images.length,
            onPageChanged: onChanged,
            itemBuilder: (_, i) => CachedNetworkImage(
              imageUrl: images[i],
              fit: BoxFit.contain,
              placeholder: (_, __) =>
                  Container(color: colors.surfaceContainerHighest),
              errorWidget: (_, __, ___) => Container(
                color: colors.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: colors.outline,
                  size: 40,
                ),
              ),
            ),
          ),
        ),
        if (images.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(images.length, (i) {
                final active = i == index;
                return Container(
                  width: active ? 16 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : colors.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _VideoView extends StatelessWidget {
  const _VideoView({required this.url, required this.cover});
  final String url;
  final String cover;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (cover.isNotEmpty)
            CachedNetworkImage(
              imageUrl: getFullImageUrl(cover),
              fit: BoxFit.cover,
              memCacheWidth: 600,
              errorWidget: (_, __, ___) =>
                  Container(color: colors.surfaceContainerHighest),
            )
          else
            Container(color: colors.surfaceContainerHighest),
          Container(
            decoration: const BoxDecoration(
              color: Colors.black38,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
          ),
        ],
      ),
    );
  }
}

class _AuthorBar extends ConsumerWidget {
  const _AuthorBar({required this.author});
  final UserEntity author;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMe = ref.watch(currentUserProvider)?.userId == author.userId;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Avatar(
            url: author.avatar,
            size: 40,
            verified: author.isVerified,
            onTap: () => context.push('/user/${author.userId}'),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: GestureDetector(
              onTap: () => context.push('/user/${author.userId}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    author.nickname,
                    style: const TextStyle(
                      fontSize: AppTextSize.title,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (author.bio.isNotEmpty)
                    Text(
                      author.bio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTextSize.caption,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!isMe)
            FollowButton(
              isFollowing: ref
                  .watch(followControllerProvider((author.userId, false)))
                  .following,
              loading: ref
                  .watch(followControllerProvider((author.userId, false)))
                  .loading,
              onTap: () => ref
                  .read(
                    followControllerProvider((author.userId, false)).notifier,
                  )
                  .toggle(),
            ),
        ],
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.postId, required this.detail});
  final int postId;
  final PostDetailEntity detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final post = detail.post;
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _showCommentInput(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm + 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: Text(
                    l.postCommentPlaceholder,
                    style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: colors.outline,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            LikeButton(
              liked: post.liked,
              count: post.likeCount,
              onTap: () =>
                  ref.read(postDetailProvider(postId).notifier).toggleLike(),
            ),
            const SizedBox(width: AppSpacing.sm),
            _IconCount(
              icon: post.collected ? Icons.bookmark : Icons.bookmark_border,
              count: post.collectCount,
              color: post.collected ? AppColors.collect : null,
              onTap: () =>
                  ref.read(postDetailProvider(postId).notifier).toggleCollect(),
            ),
            const SizedBox(width: AppSpacing.sm),
            _IconCount(
              icon: Icons.chat_bubble_outline,
              count: post.commentCount,
              onTap: () => _showCommentInput(context, ref),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _showShareMenu(context, ref, post),
            ),
          ],
        ),
      ),
    );
  }

  void _showShareMenu(BuildContext context, WidgetRef ref, PostEntity post) {
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                l.shareToChat,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(l.shareToChat),
              onTap: () async {
                Navigator.pop(context);
                await shareNoteToChat(
                  context: context,
                  ref: ref,
                  noteId: post.id,
                  title: post.title.isEmpty ? l.shareNoteTitle : post.title,
                  coverUrl: post.coverUrl.isNotEmpty
                      ? post.coverUrl
                      : (post.imageUrls.isNotEmpty
                            ? post.imageUrls.first
                            : null),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: Text(l.postShare),
              onTap: () {
                Navigator.pop(context);
                ref.read(toastControllerProvider).show(l.postShare);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCommentInput(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CommentInputSheet(postId: postId),
    );
  }
}

class _IconCount extends StatelessWidget {
  const _IconCount({
    required this.icon,
    required this.count,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final int count;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.outline;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: c),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                Formatters.count(count),
                style: TextStyle(fontSize: AppTextSize.caption, color: c),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RelatedPostsSection extends ConsumerWidget {
  const _RelatedPostsSection({required this.postId});

  final int postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(relatedPostsProvider(postId));
    final l = context.l10n;
    final tt = Theme.of(context).textTheme;

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: kPagePadding,
                child: Text(
                  l.postRelatedRecommend,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 280,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (_, i) =>
                      SizedBox(width: 140, child: PostCard(post: list[i])),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
