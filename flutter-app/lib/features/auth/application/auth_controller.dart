import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/session_event_bus.dart';
import '../../../shared/domain/user_entity.dart';
import '../../../shared/providers/core_providers.dart';
import '../data/auth_repository.dart';
import '../domain/auth_entity.dart';

class AuthController extends AsyncNotifier<AuthEntity?> {
  StreamSubscription<SessionEvent>? _sessionSub;

  @override
  Future<AuthEntity?> build() async {
    final bus = ref.watch(sessionEventBusProvider);
    _sessionSub = bus.stream.listen((event) {
      if (event == SessionEvent.expired) {
        forceLogout();
      }
    });
    ref.onDispose(() => _sessionSub?.cancel());

    final repo = ref.watch(authRepositoryProvider);
    return repo.restoreSession();
  }

  Future<void> login(String userId, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).login(userId, password),
    );
  }

  Future<void> register({
    required String userId,
    required String nickname,
    required String password,
    required String captchaId,
    required String captchaText,
    String? avatar,
    String? bio,
    String? location,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(authRepositoryProvider)
          .register(
            userId: userId,
            nickname: nickname,
            password: password,
            captchaId: captchaId,
            captchaText: captchaText,
            avatar: avatar,
            bio: bio,
            location: location,
          ),
    );
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }

  Future<void> forceLogout() async {
    await ref.read(authRepositoryProvider).clearLocal();
    state = const AsyncData(null);
  }

  Future<void> updateUser(UserEntity user) async {
    await ref.read(authRepositoryProvider).updateLocalUser(user);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(user: user));
    }
  }

  UserEntity? get currentUser => state.valueOrNull?.user;

  bool get isLoggedIn => state.valueOrNull != null;
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthEntity?>(AuthController.new);

final currentUserProvider = Provider<UserEntity?>((ref) {
  return ref.watch(authControllerProvider).valueOrNull?.user;
});
