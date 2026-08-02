import 'dart:async';

class SocketEventBus {
  final StreamController<SocketEvent> _controller =
      StreamController<SocketEvent>.broadcast();

  Stream<SocketEvent> get stream => _controller.stream;

  Stream<SocketEvent> on(String name) => stream.where((e) => e.name == name);

  void emit(String name, [dynamic data]) {
    if (!_controller.isClosed) _controller.add(SocketEvent(name, data));
  }

  void dispose() => _controller.close();
}

class SocketEvent {
  const SocketEvent(this.name, [this.data]);

  final String name;
  final dynamic data;

  @override
  String toString() => 'SocketEvent($name, $data)';
}

enum SocketConnectionState { disconnected, connecting, connected, reconnecting }
