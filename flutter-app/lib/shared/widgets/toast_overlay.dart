import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../providers/toast_controller.dart';

/// Toast 顶层覆盖层：监听 [ToastController] 流并渲染短暂提示。
///
/// 在 [MaterialApp] 的 `builder` 中包裹，使全局任意位置可弹 Toast。
class ToastOverlay extends ConsumerStatefulWidget {
  const ToastOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends ConsumerState<ToastOverlay> {
  OverlayEntry? _entry;
  Timer? _timer;
  bool _mounted = false;

  @override
  void initState() {
    super.initState();
    ref.read(toastControllerProvider).stream.listen(_show);
  }

  void _show(ToastMessage msg) {
    _timer?.cancel();
    _removeEntry();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }
    final entry = OverlayEntry(builder: (_) => _ToastView(message: msg));
    overlay.insert(entry);
    _entry = entry;
    _mounted = true;
    _timer = Timer(const Duration(seconds: 2), _removeEntry);
  }

  void _removeEntry() {
    if (_mounted && _entry != null) {
      _entry!.remove();
    }
    _entry = null;
    _mounted = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _removeEntry();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ToastView extends StatelessWidget {
  const _ToastView({required this.message});
  final ToastMessage message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      top: MediaQuery.of(context).padding.top + AppSpacing.xl,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.95) : Colors.black87,
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.type == ToastType.success)
                Icon(
                  Icons.check_circle,
                  size: 18,
                  color: isDark ? AppColors.primary : AppColors.primary,
                )
              else if (message.type == ToastType.error)
                Icon(
                  Icons.error,
                  size: 18,
                  color: isDark ? Colors.redAccent : Colors.redAccent,
                )
              else
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: isDark ? Colors.black87 : Colors.white,
                ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  message.message,
                  style: TextStyle(
                    color: isDark ? Colors.black87 : Colors.white,
                    fontSize: AppTextSize.body,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
