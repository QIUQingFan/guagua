import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// 标签 chip：`#校园` 形式，可点击。
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    this.onTap,
    this.selected = false,
    this.deletable = false,
    this.onDeleted,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final bool deletable;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.1) : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: selected ? Border.all(color: AppColors.primary.withValues(alpha: 0.3)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: selected ? AppColors.primary : colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (deletable) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onDeleted,
                child: Icon(Icons.close, size: 12, color: colors.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
