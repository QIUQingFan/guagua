import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/domain/user_entity.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/follow_button.dart';
import '../../../user/application/follow_controller.dart';
import 'highlighted_text.dart';

class SearchUserCard extends StatelessWidget {
  const SearchUserCard({
    super.key,
    required this.user,
    required this.keyword,
    this.onTap,
  });

  final UserEntity user;
  final String keyword;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final followState = ref.watch(
          followControllerProvider((user.userId, false)),
        );
        return ListTile(
          onTap: onTap,
          leading: Avatar(
            url: user.avatar,
            size: 44,
            verified: user.isVerified,
          ),
          title: HighlightedText(
            text: user.nickname,
            keyword: keyword,
            style: const TextStyle(
              fontSize: AppTextSize.title,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '瓜呱号: ${user.userId}',
            style: TextStyle(
              fontSize: AppTextSize.caption,
              color: Theme.of(context).colorScheme.outline,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: FollowButton(
            isFollowing: followState.following,
            loading: followState.loading,
            compact: true,
            onTap: () => ref
                .read(followControllerProvider((user.userId, false)).notifier)
                .toggle(),
          ),
        );
      },
    );
  }
}
