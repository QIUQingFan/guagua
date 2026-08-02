import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../application/shop_controllers.dart';
import '../../domain/shop_entities.dart';

/// 订单列表页。
class OrderListPage extends ConsumerWidget {
  const OrderListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderListControllerProvider);
    final l = context.l10n;

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.shopOrderList),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l.shopOrderAll),
              Tab(text: l.shopOrderPendingPay),
              Tab(text: l.shopOrderPendingShip),
              Tab(text: l.shopOrderPendingReceive),
              Tab(text: l.shopOrderCompleted),
            ],
            onTap: (i) {
              final status = switch (i) {
                0 => null,
                1 => OrderStatus.pendingPay.value,
                2 => OrderStatus.pendingShip.value,
                3 => OrderStatus.pendingReceive.value,
                4 => OrderStatus.completed.value,
                _ => null,
              };
              ref
                  .read(orderListControllerProvider.notifier)
                  .switchStatus(status);
            },
          ),
        ),
        body: SafeArea(child: _body(context, ref, state, l)),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    OrderListState state,
    AppLocalizations l,
  ) {
    if (state.loading && state.list.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        message: l.shopOrderEmpty,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.sm),
      itemCount: state.list.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (ctx, i) => _OrderCard(
        order: state.list[i],
        onTap: () => ctx.push('/shop/order/${state.list[i].id}'),
        onCancel: () => _cancel(ctx, ref, state.list[i].id),
        onConfirm: () => _confirm(ctx, ref, state.list[i].id),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(context.l10n.shopCancelOrderConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ref.read(orderListControllerProvider.notifier).cancel(id);
    if (!context.mounted) return;
    ref
        .read(toastControllerProvider)
        .show(
          ok
              ? context.l10n.shopOrderCancelled
              : context.l10n.commonOperationFailed,
          type: ok ? ToastType.success : ToastType.error,
        );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref, int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(context.l10n.shopConfirmReceiveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ref.read(orderListControllerProvider.notifier).confirm(id);
    if (!context.mounted) return;
    ref
        .read(toastControllerProvider)
        .show(
          ok
              ? context.l10n.shopOrderConfirmed
              : context.l10n.commonOperationFailed,
          type: ok ? ToastType.success : ToastType.error,
        );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onTap,
    required this.onCancel,
    required this.onConfirm,
  });

  final OrderEntity order;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l.shopOrderNo,
                  style: tt.bodySmall?.copyWith(color: colors.outline),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    order.orderNo,
                    style: tt.bodySmall?.copyWith(color: colors.outline),
                  ),
                ),
                Text(
                  _statusLabel(order.status, l),
                  style: TextStyle(
                    fontSize: 13,
                    color: _statusColor(order.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const Divider(height: AppSpacing.md),
            for (final item in order.items.take(2)) ...[
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.image),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: item.cover.isEmpty
                          ? Container(
                              color: colors.surfaceContainerHighest,
                              child: Icon(
                                Icons.inventory_2_outlined,
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
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.spec.isNotEmpty)
                          Text(
                            item.spec,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.outline,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    'x${item.quantity}',
                    style: TextStyle(color: colors.outline),
                  ),
                ],
              ),
              if (item != order.items.last)
                const SizedBox(height: AppSpacing.xs),
            ],
            if (order.items.length > 2)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  '共 ${order.itemCount} 件商品',
                  style: tt.bodySmall?.copyWith(color: colors.outline),
                ),
              ),
            const Divider(height: AppSpacing.md),
            Row(
              children: [
                Text(
                  l.shopOrderAmount,
                  style: tt.bodySmall?.copyWith(color: colors.outline),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${l.shopPriceSymbol}${order.totalAmount.toStringAsFixed(2)}',
                  style: tt.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                _actionButton(l),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(AppLocalizations l) {
    switch (order.status) {
      case OrderStatus.pendingPay:
        return OutlinedButton(
          onPressed: onCancel,
          child: Text(l.shopCancelOrder),
        );
      case OrderStatus.pendingReceive:
        return FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: onConfirm,
          child: Text(l.shopConfirmReceive),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  String _statusLabel(OrderStatus s, AppLocalizations l) {
    return switch (s) {
      OrderStatus.pendingPay => l.shopOrderPendingPay,
      OrderStatus.pendingShip => l.shopOrderPendingShip,
      OrderStatus.pendingReceive => l.shopOrderPendingReceive,
      OrderStatus.completed => l.shopOrderCompleted,
      OrderStatus.cancelled => l.shopOrderCancelled,
    };
  }

  Color _statusColor(OrderStatus s) {
    return switch (s) {
      OrderStatus.pendingPay => Colors.orange,
      OrderStatus.pendingShip => Colors.blue,
      OrderStatus.pendingReceive => AppColors.primary,
      OrderStatus.completed => Colors.green,
      OrderStatus.cancelled => Colors.grey,
    };
  }
}
