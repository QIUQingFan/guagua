import 'dart:async';

/// 将网络层的 401 失效事件解耦传递给状态层
class SessionEventBus {
  final StreamController<SessionEvent> _controller =
      StreamController<SessionEvent>.broadcast();

  Stream<SessionEvent> get stream => _controller.stream;

  void emit(SessionEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  void dispose() {
    _controller.close();
  }
}

/// 会话事件类型。
enum SessionEvent {
  /// token 刷新失败，需强制登出。
  expired,
}
