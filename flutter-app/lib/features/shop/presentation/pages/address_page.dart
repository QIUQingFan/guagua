import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../application/shop_controllers.dart';
import '../../data/shop_repository.dart';
import '../../domain/shop_entities.dart';

/// 地址列表页（可复用为选择器：query 参数 select=1）。
class AddressListPage extends ConsumerWidget {
  const AddressListPage({super.key, this.selectMode = false});

  final bool selectMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(addressListControllerProvider);
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l.shopSelectAddress)),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.list.isEmpty
          ? EmptyState(
              icon: Icons.location_off_outlined,
              message: l.shopNoAddress,
              actionLabel: l.shopAddAddress,
              onAction: () => _edit(context, null),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.sm),
              itemCount: state.list.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (ctx, i) => _AddressTile(
                address: state.list[i],
                onTap: () => _onTap(ctx, ref, state.list[i]),
                onEdit: () => _edit(ctx, state.list[i]),
                onDelete: () => _confirmDelete(ctx, ref, state.list[i].id),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref,
    AddressEntity address,
  ) async {
    if (selectMode) {
      ref.read(checkoutControllerProvider.notifier).setAddress(address.id);
      if (context.mounted) context.pop();
    }
  }

  Future<void> _edit(BuildContext context, AddressEntity? address) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddressEditPage(address: address)),
    );
    if (result == true) {
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    int id,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(context.l10n.commonDeleteConfirm),
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
      final ok = await ref
          .read(addressListControllerProvider.notifier)
          .remove(id);
      if (context.mounted) {
        ref
            .read(toastControllerProvider)
            .show(
              ok
                  ? context.l10n.commonDelete
                  : context.l10n.commonOperationFailed,
              type: ok ? ToastType.success : ToastType.error,
            );
      }
    }
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({
    required this.address,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final AddressEntity address;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        child: Row(
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
                        address.name,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        address.phone,
                        style: tt.bodyMedium?.copyWith(color: colors.outline),
                      ),
                      if (address.isDefault) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '默认',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address.detail,
                    style: tt.bodyMedium?.copyWith(color: colors.outline),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// 地址新增/编辑页。
class AddressEditPage extends ConsumerStatefulWidget {
  const AddressEditPage({super.key, this.address});

  final AddressEntity? address;

  @override
  ConsumerState<AddressEditPage> createState() => _AddressEditPageState();
}

class _AddressEditPageState extends ConsumerState<AddressEditPage> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _detailController = TextEditingController();
  bool _isDefault = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.address != null) {
      _nameController.text = widget.address!.name;
      _phoneController.text = widget.address!.phone;
      _detailController.text = widget.address!.detail;
      _isDefault = widget.address!.isDefault;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final detail = _detailController.text.trim();
    final l = context.l10n;

    if (name.isEmpty) {
      ref.read(toastControllerProvider).error(l.shopAddressName);
      return;
    }
    if (phone.isEmpty || phone.length < 6) {
      ref.read(toastControllerProvider).error(l.shopAddressPhone);
      return;
    }
    if (detail.isEmpty) {
      ref.read(toastControllerProvider).error(l.shopAddressDetail);
      return;
    }

    setState(() => _saving = true);
    final req = SaveAddressRequest(
      id: widget.address?.id,
      name: name,
      phone: phone,
      detail: detail,
      isDefault: _isDefault,
    );
    final ok = await ref.read(addressListControllerProvider.notifier).save(req);
    if (!mounted) return;
    setState(() => _saving = false);
    ref
        .read(toastControllerProvider)
        .show(
          ok ? l.commonSave : l.commonOperationFailed,
          type: ok ? ToastType.success : ToastType.error,
        );
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final isEdit = widget.address != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? l.shopEditAddress : l.shopAddAddress),
      ),
      body: ListView(
        padding: kPagePadding,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: l.shopAddressName,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: l.shopAddressPhone,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _detailController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l.shopAddressDetail,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile(
            title: Text(l.shopAddressDefault),
            value: _isDefault,
            onChanged: (v) => setState(() => _isDefault = v),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            ),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? l.commonLoading : l.commonSave),
          ),
        ],
      ),
    );
  }
}
