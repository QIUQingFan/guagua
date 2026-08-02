import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../../shared/providers/toast_controller.dart';

class LocationPickerSheet extends ConsumerStatefulWidget {
  const LocationPickerSheet({super.key, this.currentLocation});

  final String? currentLocation;

  static Future<String?> show(BuildContext context, {String? currentLocation}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: LocationPickerSheet(currentLocation: currentLocation),
      ),
    );
  }

  @override
  ConsumerState<LocationPickerSheet> createState() =>
      _LocationPickerSheetState();
}

class _LocationPickerSheetState extends ConsumerState<LocationPickerSheet> {
  final _manualCtrl = TextEditingController();
  bool _locating = false;

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    final l = context.l10n;
    try {
      final result = await ref.read(locationServiceProvider).getCurrent();
      await _saveAndReturn(result.address);
    } on LocationException catch (e) {
      ref.read(toastControllerProvider).error(e.message);
    } catch (_) {
      ref.read(toastControllerProvider).error(l.publishLocationFailed);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _saveAndReturn(String location) async {
    final storage = ref.read(sharedPrefsStorageProvider);
    if (storage != null) {
      await storage.addRecentLocation(location);
    }
    if (mounted) Navigator.of(context).pop(location);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final storage = ref.watch(sharedPrefsStorageProvider);
    final recent = storage?.getRecentLocations() ?? const <String>[];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.publishLocationLabel,
                    style: const TextStyle(
                      fontSize: AppTextSize.title,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.currentLocation != null &&
                    widget.currentLocation!.isNotEmpty)
                  TextButton(
                    onPressed: () => Navigator.pop(context, ''),
                    child: Text(l.publishLocationClear),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _locating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.my_location, color: AppColors.primary, size: 22),
              title: Text(
                _locating
                    ? l.publishLocationLocating
                    : l.publishLocationUseCurrent,
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: _locating ? null : _useCurrentLocation,
            ),
            const Divider(height: 1),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Text(
                  l.publishLocationRecent,
                  style: TextStyle(
                    fontSize: AppTextSize.caption,
                    color: colors.outline,
                  ),
                ),
              ),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: recent
                    .map(
                      (loc) => ActionChip(
                        label: Text(loc),
                        onPressed: () => _saveAndReturn(loc),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualCtrl,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (v) {
                      final t = v.trim();
                      if (t.isNotEmpty) _saveAndReturn(t);
                    },
                    decoration: InputDecoration(
                      hintText: l.publishLocationManualHint,
                      isDense: true,
                      prefixIcon: const Icon(Icons.edit_location_alt, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: () {
                    final t = _manualCtrl.text.trim();
                    if (t.isNotEmpty) _saveAndReturn(t);
                  },
                  child: Text(l.commonConfirm),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
