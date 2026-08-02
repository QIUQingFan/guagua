import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../../post/data/publish_repository.dart';

Future<String?> pickAndUploadChatImage(
  BuildContext context,
  WidgetRef ref,
) async {
  final l = context.l10n;
  final picker = ImagePicker();
  final XFile? file;
  try {
    file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
  } on Exception catch (_) {
    if (context.mounted) {
      ref.read(toastControllerProvider).error(l.commonOperationFailed);
    }
    return null;
  }
  if (file == null) return null;

  final uploadApi = ref.read(uploadApiProvider);
  final toast = ref.read(toastControllerProvider);

  if (!context.mounted) return null;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _UploadingDialog(),
  );

  try {
    final url = await uploadApi.uploadImage(File(file.path));
    final cleaned = cleanString(url);
    if (context.mounted) Navigator.of(context).pop(); 
    return cleaned;
  } catch (_) {
    if (context.mounted) Navigator.of(context).pop(); 
    toast.error(l.commonOperationFailed);
    return null;
  }
}

class _UploadingDialog extends StatelessWidget {
  const _UploadingDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color:
                Theme.of(context).dialogTheme.backgroundColor ??
                Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('上传中…'),
            ],
          ),
        ),
      ),
    );
  }
}
