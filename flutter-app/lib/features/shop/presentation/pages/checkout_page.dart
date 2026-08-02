import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../application/shop_controllers.dart';
import '../../data/shop_repository.dart';
import '../../domain/shop_entities.dart';

/// 结算页：选地址 → 商品清单 → 备注 → 提交订单。
class CheckoutPage extends ConsumerWidget {
  const CheckoutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(checkoutControllerProvider);
    final addressAsync = ref.watch(addressListControllerProvider);
    final defaultAddr = ref.watch(defaultAddressProvider);
    final l = context.l10n;

    if (state.addressId == null && defaultAddr != null) {
      Future.microtask(
        () => ref
            .read(checkoutControllerProvider.notifier)
            .setAddress(defaultAddr.id),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.shopCheckout)),
      body: state.placing
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _AddressCard(
                  address: addressAsync.list
                      .where((a) => a.id == state.addressId)
                      .firstOrNull,
                  defaultAddress: defaultAddr,
                  onTap: () => context.push('/shop/addresses?select=1'),
                ),
                const Divider(height: 1),
                ...state.items.map((item) => _OrderItemTile(item: item)),
                const Divider(height: 1),
                _RemarkTile(
                  value: state.remark,
                  onChanged: (v) => ref
                      .read(checkoutControllerProvider.notifier)
                      .setRemark(v),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
      bottomNavigationBar: _BottomBar(
        onSubmit: () => _placeOrder(context, ref),
        placing: state.placing,
      ),
    );
  }

  Future<void> _placeOrder(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    await ref.read(checkoutControllerProvider.notifier).placeOrder();
    if (!context.mounted) return;
    final state = ref.read(checkoutControllerProvider);
    if (state.placedOrderId != null) {
      ref.read(toastControllerProvider).success(l.shopOrderPlaced);
      context.go('/shop/order/${state.placedOrderId}');
    } else if (state.error != null) {
      ref.read(toastControllerProvider).error(l.commonOperationFailed);
    }
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.defaultAddress,
    required this.onTap,
  });

  final AddressEntity? address;
  final AddressEntity? defaultAddress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final target = address ?? defaultAddress;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: target == null
            ? Row(
                children: [
                  Icon(Icons.add_location_outlined, color: colors.outline),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    l.shopAddressEmpty,
                    style: TextStyle(color: colors.outline),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              )
            : Row(
                children: [
                  Icon(Icons.location_on, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              target.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Text(
                              target.phone,
                              style: TextStyle(color: colors.outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          target.detail,
                          style: TextStyle(color: colors.outline),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
      ),
    );
  }
}

class _OrderItemTile extends StatelessWidget {
  const _OrderItemTile({required this.item});

  final CreateOrderItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final cover = item.cover ?? '';
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.image),
        child: SizedBox(
          width: 56,
          height: 56,
          child: cover.isEmpty
              ? Container(
                  color: colors.surfaceContainerHighest,
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.grey,
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: getFullImageUrl(cover),
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: colors.surfaceContainerHighest,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey,
                    ),
                  ),
                ),
        ),
      ),
      title: Text(
        item.title ?? '商品 #${item.productId}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium,
      ),
      subtitle: Text(
        item.spec != null ? '规格: ${item.spec}' : '',
        style: TextStyle(color: colors.outline),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (item.price != null)
            Text(
              '${context.l10n.shopPriceSymbol}${item.price!.toStringAsFixed(2)}',
              style: tt.titleSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          Text('x${item.quantity}', style: TextStyle(color: colors.outline)),
        ],
      ),
    );
  }
}

class _RemarkTile extends StatelessWidget {
  const _RemarkTile({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: value ?? '');
    return ListTile(
      leading: const Icon(Icons.note_outlined),
      title: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: '订单备注（选填）',
          border: InputBorder.none,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onSubmit, required this.placing});

  final VoidCallback onSubmit;
  final bool placing;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
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
            Expanded(
              child: Text(
                l.shopCheckout,
                style: const TextStyle(
                  fontSize: 16,
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
              onPressed: placing ? null : onSubmit,
              child: Text(l.commonConfirm),
            ),
          ],
        ),
      ),
    );
  }
}
