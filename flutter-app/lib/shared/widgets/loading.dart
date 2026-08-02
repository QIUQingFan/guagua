import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// 居中加载指示器。
class LoadingSpinner extends StatelessWidget {
  const LoadingSpinner({super.key, this.size = 24, this.label});

  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final indicator = SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2.2,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
    if (label == null) return Center(child: indicator);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(height: AppSpacing.sm),
          Text(label!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 列表底部加载更多指示器。
class LoadMoreIndicator extends StatelessWidget {
  const LoadMoreIndicator({super.key, this.noMore = false});

  final bool noMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: noMore
            ? Text(
                '没有更多了',
                style: Theme.of(context).textTheme.bodySmall,
              )
            : const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
      ),
    );
  }
}
