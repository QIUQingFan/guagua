import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全局 Toast 控制器。
///
/// 通过 [ToastOverlay] 在 [MaterialApp] 顶层监听并渲染，
/// 使得 Repository / Interceptor 等无 BuildContext 的位置也能弹出提示。
///
/// 内部通过 [StreamController] 广播事件，不依赖 Notifier state。
class ToastController {
  final _controller = StreamController<ToastMessage>.broadcast();

  Stream<ToastMessage> get stream => _controller.stream;

  void show(String message, {ToastType type = ToastType.info}) {
    _controller.add(ToastMessage(message: message, type: type));
  }

  void error(String message) => show(message, type: ToastType.error);
  void success(String message) => show(message, type: ToastType.success);

  void dispose() => _controller.close();
}

final toastControllerProvider = Provider<ToastController>((ref) {
  final c = ToastController();
  ref.onDispose(c.dispose);
  return c;
});

enum ToastType { info, success, error }

class ToastMessage {
  const ToastMessage({required this.message, required this.type});
  final String message;
  final ToastType type;
}
