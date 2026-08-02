import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../constants/env.dart';
import 'socket_event_bus.dart';

/// Socket.IO 单例服务
class SocketService {
  SocketService();

  io.Socket? _socket;
  final SocketEventBus _bus = SocketEventBus();

  final StreamController<SocketConnectionState> _stateController =
      StreamController<SocketConnectionState>.broadcast();
  SocketConnectionState _state = SocketConnectionState.disconnected;

  SocketConnectionState get connectionState => _state;

  Stream<SocketConnectionState> get connectionStateStream =>
      _stateController.stream;

  SocketEventBus get bus => _bus;

  Stream<SocketEvent> on(String name) => _bus.on(name);

  bool get isConnected => _state == SocketConnectionState.connected;

  Future<void> connect(String token) async {
    if (_socket != null) {
      if (isConnected) return;
      _socket!.connect();
      return;
    }
    _setState(SocketConnectionState.connecting);

    _socket = io.io(
      Env.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!
      ..onConnect((_) {
        _setState(SocketConnectionState.connected);
        _bus.emit('connect');
      })
      ..onDisconnect((_) {
        _setState(SocketConnectionState.disconnected);
        _bus.emit('disconnect');
      })
      ..onReconnectAttempt((_) {
        _setState(SocketConnectionState.reconnecting);
        _bus.emit('reconnecting');
      })
      ..onReconnect((_) {
        _setState(SocketConnectionState.connected);
        _bus.emit('reconnect');
      })
      ..onConnectError((err) {
        _bus.emit('connect_error', err);
      })
      ..on('private:message', (data) => _bus.emit('private:message', data))
      ..on('group:message', (data) => _bus.emit('group:message', data))
      ..on('session:update', (data) => _bus.emit('session:update', data))
      ..on('private:recall', (data) => _bus.emit('private:recall', data))
      ..on('group:recall', (data) => _bus.emit('group:recall', data))
      ..on('notification:new', (data) => _bus.emit('notification:new', data))
      ..on('message:read', (data) => _bus.emit('message:read', data));

    _socket!.connect();
  }

  void emit(String event, dynamic data, {void Function(dynamic)? ack}) {
    _socket?.emitWithAck(event, data, ack: ack);
  }

  void emitNoAck(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  void disconnect() {
    _socket?.disconnect();
    _setState(SocketConnectionState.disconnected);
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
    _bus.dispose();
    _stateController.close();
  }

  void _setState(SocketConnectionState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }
}
