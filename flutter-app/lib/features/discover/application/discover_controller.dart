import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../shared/domain/post_entity.dart';
import '../../auth/application/auth_controller.dart';
import '../../post/data/post_repository.dart';
import '../../user/application/user_profile_controller.dart';

class DiscoverFeedState {
  const DiscoverFeedState({
    this.channel = 'recommend',
    this.list = const [],
    this.page = 1,
    this.hasMore = true,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  final String channel;
  final List<PostEntity> list;
  final int page;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final Object? error;

  bool get isEmpty => list.isEmpty && !loading;
  bool get hasError => error != null;

  DiscoverFeedState copyWith({
    String? channel,
    List<PostEntity>? list,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
  }) {
    return DiscoverFeedState(
      channel: channel ?? this.channel,
      list: list ?? this.list,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class DiscoverFeedController extends Notifier<DiscoverFeedState> {
  @override
  DiscoverFeedState build() {
    Future.microtask(refresh);
    return const DiscoverFeedState(loading: true);
  }

  Future<void> refresh() async {
    final channel = state.channel;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(postRepositoryProvider);
      final paged = await repo.list(category: channel, page: 1);
      state = DiscoverFeedState(
        channel: channel,
        list: paged.list,
        page: 1,
        hasMore: paged.hasMore,
      );
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e);
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.loading) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final repo = ref.read(postRepositoryProvider);
      final nextPage = state.page + 1;
      final paged = await repo.list(category: state.channel, page: nextPage);
      state = state.copyWith(
        list: [...state.list, ...paged.list],
        page: nextPage,
        hasMore: paged.hasMore,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }

  Future<void> switchChannel(String channel) async {
    if (channel == state.channel) return;
    state = DiscoverFeedState(channel: channel, loading: true);
    try {
      final repo = ref.read(postRepositoryProvider);
      final paged = await repo.list(category: channel, page: 1);
      state = DiscoverFeedState(
        channel: channel,
        list: paged.list,
        page: 1,
        hasMore: paged.hasMore,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> toggleLike(int postId) async {
    final cur = state.list.where((p) => p.id == postId).firstOrNull;
    if (cur == null) return;
    final prevLiked = cur.liked;
    final prevCount = cur.likeCount;
    state = state.copyWith(
      list: state.list
          .map(
            (p) => p.id == postId
                ? p.copyWith(
                    liked: !prevLiked,
                    likeCount: prevLiked
                        ? (prevCount > 0 ? prevCount - 1 : 0)
                        : prevCount + 1,
                  )
                : p,
          )
          .toList(),
    );
    try {
      final repo = ref.read(postRepositoryProvider);
      if (prevLiked) {
        await repo.unlikePost(postId);
      } else {
        await repo.likePost(postId);
      }
      final currentUser = ref.read(currentUserProvider);
      if (currentUser != null) {
        ref.invalidate(userProfileProvider(currentUser.userId));
      }
    } catch (_) {
      state = state.copyWith(
        list: state.list
            .map(
              (p) => p.id == postId
                  ? p.copyWith(liked: prevLiked, likeCount: prevCount)
                  : p,
            )
            .toList(),
      );
    }
  }
}

final discoverFeedProvider =
    NotifierProvider<DiscoverFeedController, DiscoverFeedState>(
      DiscoverFeedController.new,
    );

final categoriesProvider = FutureProvider<List<CategoryEntity>>((ref) async {
  return ref.watch(postRepositoryProvider).categories();
});
