import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/loading.dart';
import '../../application/shop_controllers.dart';
import '../../data/shop_repository.dart';
import '../../domain/shop_entities.dart';

/// 购物车页。
class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cartControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.shopCart)),
      body: async.when(
        loading: () => const LoadingSpinner(),
        error: (e, _) => EmptyState(
          icon: Icons.shopping_cart_outlined,
          message: e.toString(),
        ),
        data: (cart) => cart.items.isEmpty
            ? EmptyState(
                icon: Icons.shopping_cart_outlined,
                message: context.l10n.shopCartEmpty,
              )
            : _CartList(cart: cart),
      ),
      bottomNavigationBar: async.maybeWhen(
        data: (cart) => cart.items.isEmpty
            ? const SizedBox.shrink()
            : _BottomBar(cart: cart),
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }
}

class _CartList extends ConsumerWidget {
  const _CartList({required this.cart});

  final CartEntity cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.sm),
      itemCount: cart.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (ctx, i) => _CartItem(
        item: cart.items[i],
        onToggle: (selected) => ref
            .read(cartControllerProvider.notifier)
            .toggleSelect(cart.items[i].id, selected),
        onQuantity: (q) => ref
            .read(cartControllerProvider.notifier)
            .updateQuantity(cart.items[i].id, q),
        onRemove: () => _confirmRemove(ctx, ref, cart.items[i].id),
        onTap: () => ctx.push('/shop/product/${cart.items[i].productId}'),
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    int itemId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(context.l10n.shopCartDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(cartControllerProvider.notifier).remove(itemId);
    }
  }
}

class _CartItem extends StatelessWidget {
  const _CartItem({
    required this.item,
    required this.onToggle,
    required this.onQuantity,
    required this.onRemove,
    required this.onTap,
  });

  final CartItemEntity item;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onQuantity;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Dismissible(
      key: ValueKey('cart_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onRemove(),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => onToggle(!item.selected),
              child: Icon(
                item.selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 22,
                color: item.selected ? AppColors.primary : colors.outline,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              onTap: onTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.image),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: item.cover.isEmpty
                      ? Container(
                          color: colors.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_outlined,
                            color: colors.outline,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: item.cover,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: colors.surfaceContainerHighest,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: colors.outline,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium,
                  ),
                  if (item.spec.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.spec,
                      style: tt.bodySmall?.copyWith(color: colors.outline),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Text(
                        '${context.l10n.shopPriceSymbol}${item.price.toStringAsFixed(2)}',
                        style: tt.titleMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      _Stepper(
                        value: item.quantity,
                        min: 1,
                        max: item.stock > 0 ? item.stock : 99,
                        onChanged: onQuantity,
                      ),
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

class _Stepper extends StatelessWidget {
  const _Stepper({
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
        _btn(Icons.remove, () {
          if (value > min) onChanged(value - 1);
        }, colors),
        Container(
          width: 36,
          alignment: Alignment.center,
          child: Text('$value', style: const TextStyle(fontSize: 14)),
        ),
        _btn(Icons.add, () {
          if (value < max) onChanged(value + 1);
        }, colors),
      ],
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap, ColorScheme colors) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 14),
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.cart});

  final CartEntity cart;

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
            GestureDetector(
              onTap: () => ref
                  .read(cartControllerProvider.notifier)
                  .toggleSelectAll(!cart.allSelected),
              child: Row(
                children: [
                  Icon(
                    cart.allSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 22,
                    color: cart.allSelected
                        ? AppColors.primary
                        : colors.outline,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(l.shopCartSelectAll),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                l.shopCartTotal(cart.selectedTotalPrice.toStringAsFixed(2)),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
              ),
              onPressed: cart.selectedItems.isEmpty
                  ? null
                  : () => _checkout(context, ref),
              child: Text('${l.shopCheckout}(${cart.selectedCount})'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkout(BuildContext context, WidgetRef ref) async {
    final items = cart.selectedItems
        .map(
          (i) => CreateOrderItem(
            productId: i.productId,
            quantity: i.quantity,
            spec: i.spec.isEmpty ? null : i.spec,
            title: i.title,
            cover: i.cover,
            price: i.price,
          ),
        )
        .toList();
    ref.read(checkoutControllerProvider.notifier)
      ..setItems(items)
      ..setRemark(null);
    if (context.mounted) context.push('/shop/checkout');
  }
}
