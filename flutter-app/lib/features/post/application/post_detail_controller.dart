import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/post_entity.dart';
import '../../../shared/providers/toast_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../../user/application/user_profile_controller.dart';
import '../../post/data/post_repository.dart';

class PostDetailController extends FamilyAsyncNotifier<PostDetailEntity, int> {
  @override
  Future<PostDetailEntity> build(int postId) async {
    final repo = ref.watch(postRepositoryProvider);
    final detail = await repo.detail(postId);
    Future.delayed(const Duration(milliseconds: 1500), () {
      ref.read(postRepositoryProvider).view(postId);
    });
    return detail;
  }

  Future<void> toggleLike() async {
    final detail = state.valueOrNull;
    if (detail == null) return;
    final prev = detail.post;
    final next = prev.copyWith(
      liked: !prev.liked,
      likeCount: prev.liked ? prev.likeCount - 1 : prev.likeCount + 1,
    );
    state = AsyncData(detail.copyWith(post: next));
    try {
      final repo = ref.read(postRepositoryProvider);
      if (prev.liked) {
        await repo.unlikePost(prev.id);
      } else {
        await repo.likePost(prev.id);
      }
      _invalidateUserProfile();
    } catch (_) {
      state = AsyncData(detail.copyWith(post: prev));
      ref.read(toastControllerProvider).error('操作失败，请重试');
    }
  }

  Future<void> toggleCollect() async {
    final detail = state.valueOrNull;
    if (detail == null) return;
    final prev = detail.post;
    final next = prev.copyWith(
      collected: !prev.collected,
      collectCount: prev.collected
          ? prev.collectCount - 1
          : prev.collectCount + 1,
    );
    state = AsyncData(detail.copyWith(post: next));
    try {
      final repo = ref.read(postRepositoryProvider);
      if (prev.collected) {
        await repo.uncollect(prev.id);
      } else {
        await repo.collect(prev.id);
      }
      _invalidateUserProfile();
    } catch (_) {
      state = AsyncData(detail.copyWith(post: prev));
      ref.read(toastControllerProvider).error('操作失败，请重试');
    }
  }

  void _invalidateUserProfile() {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser != null) {
      ref.invalidate(userProfileProvider(currentUser.userId));
    }
  }
}

final postDetailProvider =
    AsyncNotifierProvider.family<PostDetailController, PostDetailEntity, int>(
      PostDetailController.new,
    );

final relatedPostsProvider = FutureProvider.family<List<PostEntity>, int>((
  ref,
  postId,
) async {
  return ref.watch(postRepositoryProvider).related(postId);
});
