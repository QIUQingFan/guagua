import 'package:flutter/material.dart';

/// 确认弹窗：用于删除、退出登录等危险操作的二次确认。
Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) {
  final colors = Theme.of(context).colorScheme;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel ?? '取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: colors.error)
              : TextButton.styleFrom(foregroundColor: colors.primary),
          child: Text(confirmLabel ?? '确认'),
        ),
      ],
    ),
  );
}
