import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_entity.dart';
import 'socket_event_bus.dart';
import 'socket_service.dart';

/// Socket 服务单例 Provider
final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService();
  ref.onDispose(service.dispose);

  ref.listen<AsyncValue<AuthEntity?>>(authControllerProvider, (_, next) {
    next.whenData((auth) {
      if (auth != null) {
        try {
          service.connect(auth.tokens.accessToken);
        } catch (_) {}
      } else {
        service.disconnect();
      }
    });
  });

  return service;
});

final socketConnectionStateProvider = StreamProvider<SocketConnectionState>(
  (ref) => ref.watch(socketServiceProvider).connectionStateStream,
);

final socketEventStreamProvider = StreamProvider<SocketEvent>(
  (ref) => ref.watch(socketServiceProvider).bus.stream,
);
