import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/domain/post_entity.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../application/discover_controller.dart';

/// 首页瀑布流笔记卡片
class PostCard extends ConsumerWidget {
  const PostCard({super.key, required this.post});

  final PostEntity post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => context.push('/post/${post.id}'),
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Cover(post: post),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.title.isEmpty ? post.content : post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTextSize.body,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Avatar(
                        url: post.authorAvatar,
                        size: 20,
                        verified: post.authorVerified,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          post.authorNickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTextSize.caption,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                      _LikeButton(post: post),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LikeButton extends ConsumerWidget {
  const _LikeButton({required this.post});

  final PostEntity post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(discoverFeedProvider.notifier).toggleLike(post.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              post.liked ? Icons.favorite : Icons.favorite_border,
              size: 14,
              color: post.liked
                  ? AppColors.like
                  : Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 2),
            Text(
              Formatters.count(post.likeCount),
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: post.liked
                    ? AppColors.like
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.post});
  final PostEntity post;

  @override
  Widget build(BuildContext context) {
    final cover = post.cover;
    final colors = Theme.of(context).colorScheme;
    final image = cover.isEmpty
        ? Container(
            height: 160,
            color: colors.surfaceContainerHighest,
            child: Icon(Icons.image_outlined, color: colors.outline, size: 36),
          )
        : CachedNetworkImage(
            imageUrl: getFullImageUrl(cover),
            fit: BoxFit.cover,
            memCacheWidth: 400,
            placeholder: (_, __) =>
                Container(height: 160, color: colors.surfaceContainerHighest),
            errorWidget: (_, __, ___) => Container(
              height: 160,
              color: colors.surfaceContainerHighest,
              child: Icon(Icons.broken_image_outlined, color: colors.outline),
            ),
          );

    return Stack(
      children: [
        AspectRatio(
          aspectRatio: post.isVideo ? 3 / 4 : (cover.isEmpty ? 1 : 0.75),
          child: image,
        ),
        if (post.isVideo)
          Positioned(
            top: AppSpacing.xs,
            right: AppSpacing.xs,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(AppRadius.image),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow, size: 12, color: Colors.white),
                  SizedBox(width: 2),
                  Text(
                    '视频',
                    style: TextStyle(
                      fontSize: AppTextSize.micro,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
