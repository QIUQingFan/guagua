import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/user_repository.dart';

/// 关注状态。
class FollowState {
  const FollowState({required this.following, this.loading = false, this.error});
  final bool following;
  final bool loading;
  final Object? error;

  FollowState copyWith({bool? following, bool? loading, Object? error, bool clearError = false}) {
    return FollowState(
      following: following ?? this.following,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 关注控制器：按 (目标瓜呱号, 初始是否关注) 键控。
///
/// 乐观更新 + 失败回滚；不自动拉取（初始值由调用方传入）。
/// 注意：[userId] 为瓜呱号字符串（后端 `users.user_id`），与 web 端约定一致。
class FollowController extends FamilyNotifier<FollowState, (String, bool)> {
  @override
  FollowState build((String, bool) arg) {
    return FollowState(following: arg.$2);
  }

  Future<void> toggle() async {
    final userId = arg.$1;
    final prev = state;
    if (prev.loading) return;
    state = FollowState(following: !prev.following);
    try {
      final repo = ref.read(userRepositoryProvider);
      if (prev.following) {
        await repo.unfollow(userId);
      } else {
        await repo.follow(userId);
      }
    } catch (e) {
      state = prev.copyWith(error: e);
    }
  }
}

final followControllerProvider =
    NotifierProvider.family<FollowController, FollowState, (String, bool)>(
  FollowController.new,
);
