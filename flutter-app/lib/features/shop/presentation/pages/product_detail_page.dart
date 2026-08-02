import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../../../shared/widgets/error_retry.dart';
import '../../../../shared/widgets/loading.dart';
import '../../../chat/application/chat_list_controller.dart';
import '../../../chat/data/chat_repository.dart';
import '../../application/shop_controllers.dart';
import '../../data/shop_repository.dart';
import '../../domain/shop_entities.dart';

/// 商品详情页数量状态（按商品 ID 区分）。
final _productQuantityProvider = StateProvider.family<int, int>((ref, id) => 1);

/// 移除 HTML 标签，得到纯文本（用于商品描述展示）。
String _stripHtml(String html) {
  return html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();
}

/// 商品详情页。
class ProductDetailPage extends ConsumerWidget {
  const ProductDetailPage({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(productDetailProvider(id));
    return Scaffold(
      body: async.when(
        loading: () => const LoadingSpinner(),
        error: (e, _) => ErrorRetryView(
          message: e.toString(),
          onRetry: () => ref.invalidate(productDetailProvider(id)),
        ),
        data: (product) => _Body(product: product),
      ),
      bottomNavigationBar: async.maybeWhen(
        data: (product) => _BottomBar(product: product),
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.product});

  final ProductEntity product;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  int _currentImage = 0;
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: false,
          expandedHeight: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.shopping_cart_outlined),
              onPressed: () => context.push('/shop/cart'),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: product.images.isEmpty
              ? Container(
                  height: 360,
                  color: colors.surfaceContainerHighest,
                  child: Icon(
                    Icons.image_outlined,
                    size: 64,
                    color: colors.outline,
                  ),
                )
              : SizedBox(
                  height: 360,
                  child: Stack(
                    children: [
                      PageView(
                        controller: _pageController,
                        onPageChanged: (i) => setState(() => _currentImage = i),
                        children: product.images
                            .map(
                              (url) => CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  color: colors.surfaceContainerHighest,
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: colors.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: colors.outline,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      if (product.images.length > 1)
                        Positioned(
                          bottom: AppSpacing.md,
                          right: AppSpacing.md,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(
                                AppRadius.chip,
                              ),
                            ),
                            child: Text(
                              '${_currentImage + 1}/${product.images.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: kPagePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${l.shopPriceSymbol}${product.price.toStringAsFixed(2)}',
                      style: tt.displayMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (product.hasDiscount) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${l.shopPriceSymbol}${product.originalPrice!.toStringAsFixed(2)}',
                          style: tt.bodySmall?.copyWith(
                            color: colors.outline,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  product.title,
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Text(
                      l.shopSold(product.salesCount),
                      style: tt.bodySmall?.copyWith(color: colors.outline),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      l.shopStock(product.stock),
                      style: tt.bodySmall?.copyWith(color: colors.outline),
                    ),
                  ],
                ),
                const Divider(height: AppSpacing.xl),
                if (product.specs.isNotEmpty) ...[
                  for (final spec in product.specs) ...[
                    Text('${l.shopSpec}: ${spec.name}', style: tt.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: spec.values
                          .map((v) => Chip(label: Text(v)))
                          .toList(),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],
                Row(
                  children: [
                    Text(l.shopQuantity, style: tt.titleMedium),
                    const Spacer(),
                    _QuantityStepper(
                      value: ref.watch(_productQuantityProvider(product.id)),
                      min: 1,
                      max: product.stock > 0 ? product.stock : 99,
                      onChanged: (v) =>
                          ref
                                  .read(
                                    _productQuantityProvider(
                                      product.id,
                                    ).notifier,
                                  )
                                  .state =
                              v,
                    ),
                  ],
                ),
                const Divider(height: AppSpacing.xl),
                Text(l.shopProductDetail, style: tt.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _stripHtml(
                    product.description.isEmpty
                        ? product.title
                        : product.description,
                  ),
                  style: tt.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: _RelatedSection(productId: product.id)),
      ],
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.product});

  final ProductEntity product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            _BottomAction(
              icon: product.sellerId == kPlatformSupportUserId
                  ? Icons.support_agent_outlined
                  : Icons.chat_outlined,
              label: product.sellerId == kPlatformSupportUserId
                  ? l.shopContactPlatform
                  : l.shopContactSeller,
              onTap: () => _contactSeller(context, ref),
            ),
            _BottomAction(
              icon: Icons.shopping_cart_outlined,
              label: l.shopCart,
              onTap: () => context.push('/shop/cart'),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
                onPressed: () => _addToCart(context, ref),
                child: Text(l.shopAddCart),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
                onPressed: () => _buyNow(context, ref),
                child: Text(l.shopBuyNow),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addToCart(BuildContext context, WidgetRef ref) async {
    final quantity = ref.read(_productQuantityProvider(product.id));
    try {
      await ref.read(cartControllerProvider.notifier).add(product.id, quantity);
      if (context.mounted) {
        ref.read(toastControllerProvider).success(context.l10n.shopAddedToCart);
      }
    } catch (_) {
      if (context.mounted) {
        ref
            .read(toastControllerProvider)
            .error(context.l10n.commonOperationFailed);
      }
    }
  }

  Future<void> _buyNow(BuildContext context, WidgetRef ref) async {
    final quantity = ref.read(_productQuantityProvider(product.id));
    ref.read(checkoutControllerProvider.notifier)
      ..setItems([
        CreateOrderItem(
          productId: product.id,
          quantity: quantity,
          title: product.title,
          cover: product.cover,
          price: product.price,
        ),
      ])
      ..setRemark(null);
    if (context.mounted) context.push('/shop/checkout');
  }

  Future<void> _contactSeller(BuildContext context, WidgetRef ref) async {
    final sellerId = product.sellerId;
    final l = context.l10n;
    try {
      final cached = ref.read(chatListControllerProvider).sessions;
      final session = await ref
          .read(chatRepositoryProvider)
          .ensurePrivateSession(targetUserId: sellerId, cached: cached);
      if (!context.mounted) return;
      ref.read(chatListControllerProvider.notifier).refresh();
      context.push('/chat/${session.id}');
    } catch (_) {
      if (context.mounted) {
        ref.read(toastControllerProvider).error(l.shopContactSellerFailed);
      }
    }
  }
}

/// 底部操作按钮：图标 + 文案。
class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: colors.onSurfaceVariant),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// 相关推荐区块：横向滑动展示同类目商品。
class _RelatedSection extends ConsumerWidget {
  const _RelatedSection({required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(relatedProductsProvider(productId));
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
                  l.shopRelatedRecommend,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 200,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (_, i) => _RelatedProductCard(product: list[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 相关推荐商品卡片。
class _RelatedProductCard extends StatelessWidget {
  const _RelatedProductCard({required this.product});

  final ProductEntity product;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l = context.l10n;
    return GestureDetector(
      onTap: () => context.push('/shop/product/${product.id}'),
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 120,
              width: double.infinity,
              child: product.images.isEmpty
                  ? Container(
                      color: colors.surfaceContainerHighest,
                      child: Icon(Icons.image_outlined, color: colors.outline),
                    )
                  : CachedNetworkImage(
                      imageUrl: product.images.first,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${l.shopPriceSymbol}${product.price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
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

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(Icons.remove, () {
          if (value > min) onChanged(value - 1);
        }, colors),
        Container(
          width: 48,
          alignment: Alignment.center,
          child: Text('$value', style: const TextStyle(fontSize: 16)),
        ),
        _button(Icons.add, () {
          if (value < max) onChanged(value + 1);
        }, colors),
      ],
    );
  }

  Widget _button(IconData icon, VoidCallback onTap, ColorScheme colors) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 16),
      ),
    );
  }
}
