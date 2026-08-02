import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/widgets/error_retry.dart';
import '../../../../shared/widgets/loading.dart';
import '../../application/shop_controllers.dart';
import '../../domain/shop_entities.dart';

/// 订单详情页。
///
/// 该页面有两种进入方式：
/// 1. 从订单列表 `context.push` 进入 —— 默认返回按钮可用。
/// 2. 下单成功后从结算页 `context.go` 进入（替换栈）—— 此时栈底无上一级，
///    需要显式 `leading` 回落到订单列表，避免左上角缺少返回入口。
class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderDetailProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.shopOrderDetail),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/shop/orders');
            }
          },
        ),
      ),
      body: async.when(
        loading: () => const LoadingSpinner(),
        error: (e, _) => ErrorRetryView(
          message: e.toString(),
          onRetry: () => ref.invalidate(orderDetailProvider(id)),
        ),
        data: (order) => _Body(order: order),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.order});

  final OrderEntity order;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListView(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          color: _statusColor(order.status).withValues(alpha: 0.1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _statusLabel(order.status, l),
                style: tt.titleLarge?.copyWith(
                  color: _statusColor(order.status),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        ListTile(
          leading: Icon(Icons.location_on, color: AppColors.primary),
          title: Text('${order.addressName}  ${order.addressPhone}'),
          subtitle: Text(order.addressDetail),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text('商品清单', style: tt.titleMedium),
        ),
        for (final item in order.items)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.image),
                  child: SizedBox(
                    width: 64,
                    height: 64,
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.spec.isNotEmpty)
                        Text(
                          item.spec,
                          style: TextStyle(fontSize: 12, color: colors.outline),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${l.shopPriceSymbol}${item.price.toStringAsFixed(2)}',
                    ),
                    Text(
                      'x${item.quantity}',
                      style: TextStyle(color: colors.outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              _infoRow(l.shopOrderNo, order.orderNo, tt, colors),
              _infoRow(
                l.shopOrderTime,
                Formatters.dateTime(order.createdAt),
                tt,
                colors,
              ),
              _infoRow(
                l.shopOrderAmount,
                '${l.shopPriceSymbol}${order.totalAmount.toStringAsFixed(2)}',
                tt,
                colors,
                valueColor: AppColors.primary,
                bold: true,
              ),
              if (order.remark != null && order.remark!.isNotEmpty)
                _infoRow('备注', order.remark!, tt, colors),
            ],
          ),
        ),
        if (order.statusLogs.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text('订单进度', style: tt.titleMedium),
          ),
          for (final log in order.statusLogs)
            ListTile(
              leading: Icon(
                Icons.check_circle,
                color: _statusColor(log.status),
                size: 20,
              ),
              title: Text(_statusLabel(log.status, l)),
              subtitle: Text(log.displayTime),
            ),
        ],
      ],
    );
  }

  Widget _infoRow(
    String label,
    String value,
    TextTheme tt,
    ColorScheme colors, {
    Color? valueColor,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Text(label, style: tt.bodyMedium?.copyWith(color: colors.outline)),
          const Spacer(),
          Text(
            value,
            style: tt.bodyMedium?.copyWith(
              color: valueColor ?? colors.onSurface,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
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
