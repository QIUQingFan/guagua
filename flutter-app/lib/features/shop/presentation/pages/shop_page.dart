import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry.dart';
import '../../application/shop_controllers.dart';
import '../../domain/shop_entities.dart';

/// 商城首页：搜索栏 + 分类横滑 + 双列商品瀑布流 + 购物车入口。
class ShopPage extends ConsumerWidget {
  const ShopPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(productListControllerProvider);
    final categoriesAsync = ref.watch(productCategoriesProvider);
    final cartCount = ref.watch(cartCountProvider);
    final l = context.l10n;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/ai/chat'),
        icon: const Icon(Icons.smart_toy_outlined),
        label: Text(l.aiTitle),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => context.push('/shop/search'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search,
                              size: 18,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              l.shopSearchHint,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.outline,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    onPressed: () => context.push('/shop/cart'),
                    icon: Badge(
                      isLabelVisible: cartCount > 0,
                      label: Text(cartCount > 99 ? '99+' : '$cartCount'),
                      child: const Icon(Icons.shopping_cart_outlined),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: categoriesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (cats) => ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  children: [
                    _CategoryChip(
                      label: l.shopCategoryAll,
                      selected: state.categoryId == null,
                      onTap: () => ref
                          .read(productListControllerProvider.notifier)
                          .switchCategory(null),
                    ),
                    for (final c in cats)
                      _CategoryChip(
                        label: c.name,
                        selected: state.categoryId == c.id,
                        onTap: () => ref
                            .read(productListControllerProvider.notifier)
                            .switchCategory(c.id),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _productList(context, ref, state, l)),
          ],
        ),
      ),
    );
  }

  Widget _productList(
    BuildContext context,
    WidgetRef ref,
    ProductListState state,
    AppLocalizations l,
  ) {
    if (state.loading && state.list.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError && state.list.isEmpty) {
      return ErrorRetryView(
        message: l.commonNetworkError,
        onRetry: () =>
            ref.read(productListControllerProvider.notifier).refresh(),
      );
    }
    if (state.isEmpty) {
      return EmptyState(
        icon: Icons.storefront_outlined,
        message: l.shopProductEmpty,
      );
    }
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(productListControllerProvider.notifier).refresh(),
      child: GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.sm),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 0.65,
        ),
        itemCount: state.list.length + (state.hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i >= state.list.length) {
            Future.microtask(
              () => ref.read(productListControllerProvider.notifier).loadMore(),
            );
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return _ProductCard(product: state.list[i]);
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : colors.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final ProductEntity product;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => context.push('/shop/product/${product.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: product.cover.isEmpty
                  ? Container(
                      color: colors.surfaceContainerHighest,
                      child: Icon(Icons.image_outlined, color: colors.outline),
                    )
                  : CachedNetworkImage(
                      imageUrl: product.cover,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: colors.surfaceContainerHighest),
                      errorWidget: (_, __, ___) => Container(
                        color: colors.surfaceContainerHighest,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: colors.outline,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${l10nPriceSymbol(context)}${product.price.toStringAsFixed(2)}',
                        style: tt.titleMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (product.hasDiscount) ...[
                        const SizedBox(width: 4),
                        Text(
                          '${l10nPriceSymbol(context)}${product.originalPrice!.toStringAsFixed(2)}',
                          style: tt.bodySmall?.copyWith(
                            color: colors.outline,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10nSold(context, product.salesCount),
                    style: tt.bodySmall?.copyWith(color: colors.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String l10nPriceSymbol(BuildContext context) => context.l10n.shopPriceSymbol;
  String l10nSold(BuildContext context, int count) =>
      context.l10n.shopSold(count);
}
