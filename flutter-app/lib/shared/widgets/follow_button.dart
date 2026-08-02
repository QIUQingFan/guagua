import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// 关注按钮（受控）。
///
/// 状态由父级 Provider 管理（乐观更新 + 回滚）；按钮仅负责渲染与点击回调。
class FollowButton extends StatelessWidget {
  const FollowButton({
    super.key,
    required this.isFollowing,
    required this.onTap,
    this.compact = false,
    this.loading = false,
  });

  final bool isFollowing;
  final bool loading;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = isFollowing ? '已关注' : '＋关注';

    if (compact) {
      return GestureDetector(
        onTap: loading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: isFollowing ? colors.surfaceContainerHighest : AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: isFollowing ? Border.all(color: colors.outlineVariant) : null,
          ),
          child: loading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: isFollowing ? colors.onSurface : Colors.white),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: AppTextSize.caption,
                    fontWeight: FontWeight.w600,
                    color: isFollowing ? colors.onSurface : Colors.white,
                  ),
                ),
        ),
      );
    }

    return OutlinedButton(
      onPressed: loading ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: isFollowing ? colors.onSurface : Colors.white,
        backgroundColor: isFollowing ? colors.surfaceContainerHighest : AppColors.primary,
        side: isFollowing ? BorderSide(color: colors.outlineVariant) : BorderSide.none,
        minimumSize: const Size(96, 36),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
      ),
      child: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isFollowing ? colors.onSurface : Colors.white,
              ),
            )
          : Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppTextSize.body)),
    );
  }
}
