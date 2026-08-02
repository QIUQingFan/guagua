import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/formatters.dart';

/// 点赞按钮（受控）：爱心 + 计数，带缩放回弹动画。
class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.liked,
    required this.count,
    required this.onTap,
    this.iconColor,
  });

  final bool liked;
  final int count;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.liked) {
      _controller.forward(from: 0.0).then((_) => _controller.reverse());
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.liked ? AppColors.like : Theme.of(context).colorScheme.outline;
    return InkWell(
      onTap: _handleTap,
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.3).animate(
                CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
              ),
              child: Icon(
                widget.liked ? Icons.favorite : Icons.favorite_border,
                size: 20,
                color: widget.iconColor ?? color,
              ),
            ),
            if (widget.count > 0) ...[
              const SizedBox(width: 4),
              Text(
                Formatters.count(widget.count),
                style: TextStyle(fontSize: AppTextSize.caption, color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
