import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../shared/domain/post_entity.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../../../shared/widgets/tag_chip.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../user/application/user_profile_controller.dart';
import '../../application/publish_controller.dart';
import '../../data/post_repository.dart';
import '../widgets/location_picker_sheet.dart';
import '../widgets/publish_media_grid.dart';

class PublishPage extends ConsumerStatefulWidget {
  const PublishPage({super.key});

  @override
  ConsumerState<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends ConsumerState<PublishPage> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _tagController = TextEditingController();
  final _picker = ImagePicker();
  bool _restored = false;
  bool _hasShownRestorePrompt = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _syncControllersFromState(PublishFormState form) {
    if (_titleController.text != form.title) {
      _titleController.value = TextEditingValue(
        text: form.title,
        selection: TextSelection.collapsed(offset: form.title.length),
      );
    }
    if (_contentController.text != form.content) {
      _contentController.value = TextEditingValue(
        text: form.content,
        selection: TextSelection.collapsed(offset: form.content.length),
      );
    }
  }

  String? _categoryName(int? categoryId) {
    if (categoryId == null) return null;
    final cats = ref.read(categoryListForPublishProvider).valueOrNull;
    if (cats == null) return categoryId.toString();
    final cat = cats.where((c) => c.id == categoryId).firstOrNull;
    return cat?.name ?? categoryId.toString();
  }

  Future<void> _pickImages() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 80, limit: 9);
      if (files.isEmpty) return;
      final remaining =
          9 - ref.read(publishControllerProvider).form.localImages.length;
      if (remaining <= 0) {
        ref.read(toastControllerProvider).show(context.l10n.publishImageLimit);
        return;
      }
      final paths = files.take(remaining).map((f) => f.path).toList();
      ref.read(publishControllerProvider.notifier).addImages(paths);
    } catch (_) {
      ref
          .read(toastControllerProvider)
          .error(context.l10n.commonOperationFailed);
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 60),
      );
      if (file == null) return;
      ref.read(publishControllerProvider.notifier).setVideo(file.path);
    } catch (_) {
      ref
          .read(toastControllerProvider)
          .error(context.l10n.commonOperationFailed);
    }
  }

  Future<void> _onPublish() async {
    final l = context.l10n;
    ref.read(publishControllerProvider.notifier)
      ..setTitle(_titleController.text)
      ..setContent(_contentController.text);
    await ref.read(publishControllerProvider.notifier).publish();

    if (!mounted) return;
    final state = ref.read(publishControllerProvider);
    if (state.status == PublishStatus.success && state.createdPostId != null) {
      ref.read(toastControllerProvider).success(l.publishSuccess);
      ref.read(publishControllerProvider.notifier).reset();
      final currentUser = ref.read(currentUserProvider);
      if (currentUser != null) {
        ref.invalidate(userProfileProvider(currentUser.userId));
      }
      context.go('/post/${state.createdPostId}');
    } else if (state.errorCode != null) {
      final msg = _translateError(state.errorCode!, l);
      ref.read(toastControllerProvider).error(msg);
    }
  }

  String _translateError(String code, AppLocalizations l) {
    switch (code) {
      case 'need_title':
        return l.publishNeedTitle;
      case 'need_media':
        return l.publishNeedMedia;
      case 'unauthorized':
        return l.toastUnauthorized;
      case 'server_error':
        return l.toastServerError;
      case 'network_error':
        return l.toastNetworkError;
      default:
        return l.commonOperationFailed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(publishControllerProvider);
    final l = context.l10n;
    ref.watch(categoryListForPublishProvider);

    ref.listen<PublishState>(publishControllerProvider, (prev, next) {
      final prevTitle = prev?.form.title;
      final nextTitle = next.form.title;
      if (prevTitle != nextTitle && nextTitle != _titleController.text) {
        _titleController.value = TextEditingValue(
          text: nextTitle,
          selection: TextSelection.collapsed(offset: nextTitle.length),
        );
      }
      final prevContent = prev?.form.content;
      final nextContent = next.form.content;
      if (prevContent != nextContent &&
          nextContent != _contentController.text) {
        _contentController.value = TextEditingValue(
          text: nextContent,
          selection: TextSelection.collapsed(offset: nextContent.length),
        );
      }
    });

    if (!_hasShownRestorePrompt) {
      _hasShownRestorePrompt = true;
      Future.microtask(() {
        if (!mounted) return;
        _syncControllersFromState(state.form);
        _maybePromptRestore(state.form);
      });
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _onExit(context, state.form),
        ),
        title: Text(l.publishTitle),
        actions: [
          if (state.isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _onPublish,
              child: Text(
                l.publishSubmit,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: kPagePadding,
              children: [
                _buildModeSwitch(context, state.form),
                const SizedBox(height: AppSpacing.md),
                PublishMediaGrid(
                  isVideo: state.form.isVideo,
                  images: state.form.localImages,
                  video: state.form.localVideo,
                  onAddImages: _pickImages,
                  onPickVideo: _pickVideo,
                  onRemoveImage: (i) => ref
                      .read(publishControllerProvider.notifier)
                      .removeImageAt(i),
                  onReorderImages: (o, n) => ref
                      .read(publishControllerProvider.notifier)
                      .reorderImages(o, n),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _titleController,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: l.publishTitleHint,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLength: 30,
                ),
                const Divider(height: 1),
                TextField(
                  controller: _contentController,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: l.publishContentHint,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  maxLines: 6,
                  minLines: 3,
                  maxLength: 2000,
                ),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                _buildTagInput(context, state.form, l),
                const SizedBox(height: AppSpacing.sm),
                _buildOptionRow(
                  context,
                  icon: Icons.category_outlined,
                  label: l.publishCategoryLabel,
                  value: _categoryName(state.form.categoryId),
                  onTap: () => _showCategoryPicker(context, ref),
                ),
                _buildOptionRow(
                  context,
                  icon: Icons.location_on_outlined,
                  label: l.publishLocationLabel,
                  value: state.form.location,
                  onTap: () => _editLocation(context, ref, state.form.location),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: state.isBusy
                            ? null
                            : () async {
                                ref.read(publishControllerProvider.notifier)
                                  ..setTitle(_titleController.text)
                                  ..setContent(_contentController.text);
                                await ref
                                    .read(publishControllerProvider.notifier)
                                    .saveDraft();
                                if (!mounted) return;
                                ref
                                    .read(toastControllerProvider)
                                    .success(l.publishDraftSaved);
                                context.pop();
                              },
                        child: Text(l.publishSaveDraft),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton(
                        onPressed: state.isBusy ? null : _onPublish,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        child: Text(l.publishSubmit),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (state.status == PublishStatus.uploading ||
                state.status == PublishStatus.publishing)
              _buildProgressDialog(context, state, l),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSwitch(BuildContext context, PublishFormState form) {
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _modeChip(
              context,
              label: l.publishModeImage,
              selected: !form.isVideo,
              onTap: () =>
                  ref.read(publishControllerProvider.notifier).switchType(1),
            ),
          ),
          Expanded(
            child: _modeChip(
              context,
              label: l.publishModeVideo,
              selected: form.isVideo,
              onTap: () =>
                  ref.read(publishControllerProvider.notifier).switchType(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTagInput(
    BuildContext context,
    PublishFormState form,
    AppLocalizations l,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tag, size: 18, color: colors.outline),
            const SizedBox(width: AppSpacing.xs),
            Text(l.publishTagsLabel, style: const TextStyle(fontSize: 14)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final tag in form.tags)
              TagChip(
                label: '#$tag',
                deletable: true,
                onDeleted: () =>
                    ref.read(publishControllerProvider.notifier).removeTag(tag),
              ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _tagController,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: l.publishTagPlaceholder,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colors.surfaceContainerHighest,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () {
                      final v = _tagController.text.trim();
                      if (v.isNotEmpty) {
                        ref.read(publishControllerProvider.notifier).addTag(v);
                        _tagController.clear();
                      }
                    },
                  ),
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) {
                    ref.read(publishControllerProvider.notifier).addTag(v);
                  }
                  _tagController.clear();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOptionRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? value,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.outline),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
            if (value != null && value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: Text(
                  value,
                  style: TextStyle(fontSize: 13, color: colors.outline),
                ),
              ),
            Icon(Icons.chevron_right, size: 20, color: colors.outline),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressDialog(
    BuildContext context,
    PublishState state,
    AppLocalizations l,
  ) {
    final isUploading = state.status == PublishStatus.uploading;
    final progress = state.uploadTotal > 0
        ? state.uploadProgress / state.uploadTotal
        : 0.0;
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isUploading && state.uploadTotal > 1)
                Text(
                  l.publishUploadProgress(
                    state.uploadProgress,
                    state.uploadTotal,
                  ),
                  style: const TextStyle(fontSize: 14),
                )
              else
                Text(
                  isUploading ? l.publishUploading : l.publishSubmit,
                  style: const TextStyle(fontSize: 14),
                ),
              const SizedBox(height: AppSpacing.md),
              LinearProgressIndicator(value: isUploading ? progress : null),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _maybePromptRestore(PublishFormState form) async {
    if (_restored) return;
    if (form.title.isEmpty &&
        form.content.isEmpty &&
        form.localImages.isEmpty &&
        form.localVideo == null) {
      return;
    }
    _restored = true;
    if (!mounted) return;
    final l = context.l10n;
    final shouldRestore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l.publishTitle),
        content: Text(l.publishDraftRestoreConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.publishDraftDiscard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.publishDraftRestore),
          ),
        ],
      ),
    );
    if (shouldRestore != true) {
      await ref.read(publishControllerProvider.notifier).discardDraft();
    }
  }

  Future<void> _onExit(BuildContext context, PublishFormState form) async {
    ref.read(publishControllerProvider.notifier)
      ..setTitle(_titleController.text)
      ..setContent(_contentController.text);
    final latestForm = ref.read(publishControllerProvider).form;
    final hasContent =
        latestForm.title.isNotEmpty ||
        latestForm.content.isNotEmpty ||
        latestForm.localImages.isNotEmpty ||
        latestForm.localVideo != null;
    if (!hasContent) {
      context.pop();
      return;
    }
    final l = context.l10n;
    final action = await showDialog<_ExitAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.publishDraftRestoreConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ExitAction.discard),
            child: Text(l.publishDraftDiscard),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ExitAction.draft),
            child: Text(l.publishSaveDraft),
          ),
        ],
      ),
    );
    switch (action) {
      case _ExitAction.draft:
        await ref.read(publishControllerProvider.notifier).saveDraft();
        if (mounted) context.pop();
      case _ExitAction.discard:
        await ref.read(publishControllerProvider.notifier).discardDraft();
        if (mounted) context.pop();
      default:
        break;
    }
  }

  Future<void> _showCategoryPicker(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final cats = await ref.read(categoryListForPublishProvider.future);
    if (!mounted) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                l.publishSelectCategory,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final c in cats)
              ListTile(
                title: Text(c.name),
                onTap: () => Navigator.pop(ctx, c.id),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      ref.read(publishControllerProvider.notifier).setCategoryId(selected);
    }
  }

  Future<void> _editLocation(
    BuildContext context,
    WidgetRef ref,
    String? current,
  ) async {
    final result = await LocationPickerSheet.show(
      context,
      currentLocation: current,
    );
    if (result != null) {
      ref
          .read(publishControllerProvider.notifier)
          .setLocation(result.isEmpty ? null : result);
    }
  }
}

enum _ExitAction { draft, discard }

final categoryListForPublishProvider = FutureProvider<List<CategoryEntity>>((
  ref,
) async {
  return ref.watch(postRepositoryProvider).categories();
});
