import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../application/discover_controller.dart';

/// 顶部频道切换栏
class ChannelBar extends ConsumerWidget {
  const ChannelBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final categoriesAsync = ref.watch(categoriesProvider);
    final current = ref.watch(discoverFeedProvider).channel;

    final channels = <_Channel>[
      _Channel(id: 'recommend', name: l.discoverRecommend),
    ];
    categoriesAsync.whenOrNull(
      data: (list) => channels.addAll(
        list.map((c) => _Channel(id: c.id.toString(), name: c.name)),
      ),
    );

    return Container(
      height: 44,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: channels.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.lg),
        itemBuilder: (_, i) {
          final ch = channels[i];
          final selected = ch.id == current;
          return GestureDetector(
            onTap: () =>
                ref.read(discoverFeedProvider.notifier).switchChannel(ch.id),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  ch.name,
                  style: TextStyle(
                    fontSize: AppTextSize.title,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected
                        ? AppColors.primary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 18,
                  height: 3,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Channel {
  const _Channel({required this.id, required this.name});
  final String id;
  final String name;
}
