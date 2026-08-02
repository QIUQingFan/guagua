import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/post_entity.dart';
import '../../../shared/domain/user_entity.dart';
import '../data/user_dto.dart';
import '../data/user_repository.dart';

/// 用户主页 Tab。
enum UserProfileTab { posts, collections, likes }

/// 用户主页分页状态。
class _PagedState<T> {
  const _PagedState({
    this.list = const [],
    this.page = 1,
    this.hasMore = true,
    this.loading = false,
  });

  final List<T> list;
  final int page;
  final bool hasMore;
  final bool loading;

  _PagedState<T> copyWith({
    List<T>? list,
    int? page,
    bool? hasMore,
    bool? loading,
  }) {
    return _PagedState<T>(
      list: list ?? this.list,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
    );
  }
}

/// 用户主页状态。
class UserProfileState {
  const UserProfileState({
    this.user,
    this.stats,
    this.posts = const _PagedState<PostEntity>(),
    this.collections = const _PagedState<PostEntity>(),
    this.likes = const _PagedState<PostEntity>(),
    this.activeTab = UserProfileTab.posts,
    this.loading = true,
    this.error,
  });

  final UserEntity? user;
  final UserStatsEntity? stats;
  final _PagedState<PostEntity> posts;
  final _PagedState<PostEntity> collections;
  final _PagedState<PostEntity> likes;
  final UserProfileTab activeTab;
  final bool loading;
  final Object? error;

  UserProfileState copyWith({
    UserEntity? user,
    UserStatsEntity? stats,
    _PagedState<PostEntity>? posts,
    _PagedState<PostEntity>? collections,
    _PagedState<PostEntity>? likes,
    UserProfileTab? activeTab,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) {
    return UserProfileState(
      user: user ?? this.user,
      stats: stats ?? this.stats,
      posts: posts ?? this.posts,
      collections: collections ?? this.collections,
      likes: likes ?? this.likes,
      activeTab: activeTab ?? this.activeTab,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 用户主页控制器：以瓜呱号 `userId`（字符串）键控。
///
/// 注意：所有用户相关接口的 `userId` 参数均为**瓜呱号字符串**
/// （后端 `users.user_id`，如 `guagua_001`），不是自增数字主键 `id`。
class UserProfileController
    extends FamilyAsyncNotifier<UserProfileState, String> {
  @override
  Future<UserProfileState> build(String userId) async {
    final repo = ref.watch(userRepositoryProvider);
    try {
      final results = await Future.wait([
        repo.detail(userId),
        repo.stats(userId),
      ]);
      final user = results[0] as UserEntity;
      final stats = results[1] as UserStatsEntity;
      var state = UserProfileState(user: user, stats: stats, loading: false);
      state = await _loadPosts(userId, state);
      return state;
    } catch (e) {
      return UserProfileState(loading: false, error: e);
    }
  }

  /// 刷新整个页面。
  Future<void> refresh() async {
    final userId = arg;
    state = const AsyncLoading();
    state = AsyncData(await build(userId));
  }

  /// 切换 Tab。
  Future<void> switchTab(UserProfileTab tab) async {
    final current = state.valueOrNull;
    if (current == null || current.activeTab == tab) return;
    state = AsyncData(current.copyWith(activeTab: tab, clearError: true));
    final afterSwitch = state.valueOrNull ?? current;
    if (tab == UserProfileTab.collections &&
        afterSwitch.collections.list.isEmpty) {
      await _loadCollections(arg, afterSwitch);
    } else if (tab == UserProfileTab.likes && afterSwitch.likes.list.isEmpty) {
      await _loadLikes(arg, afterSwitch);
    }
  }

  /// 加载更多当前 Tab。
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.activeTab == UserProfileTab.posts) {
      await _loadMorePosts(arg, current);
    } else if (current.activeTab == UserProfileTab.collections) {
      await _loadMoreCollections(arg, current);
    } else {
      await _loadMoreLikes(arg, current);
    }
  }

  /// 更新用户资料（编辑资料后调用，刷新当前页）。
  Future<void> updateUser(UserEntity user) async {
    final current = state.valueOrNull;
    if (current == null || current.user?.id != user.id) return;
    state = AsyncData(current.copyWith(user: user));
  }

  Future<UserProfileState> _loadPosts(
    String userId,
    UserProfileState current,
  ) async {
    try {
      final paged = await ref
          .read(userRepositoryProvider)
          .posts(userId, page: 1);
      final next = current.copyWith(
        posts: _PagedState<PostEntity>(
          list: paged.list,
          hasMore: paged.hasMore,
        ),
      );
      state = AsyncData(next);
      return next;
    } catch (e, st) {
      debugPrint('UserProfileController._loadPosts($userId) failed: $e\n$st');
      return current;
    }
  }

  Future<void> _loadCollections(String userId, UserProfileState current) async {
    try {
      final paged = await ref
          .read(userRepositoryProvider)
          .collections(userId, page: 1);
      state = AsyncData(
        current.copyWith(
          collections: _PagedState<PostEntity>(
            list: paged.list,
            hasMore: paged.hasMore,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint(
        'UserProfileController._loadCollections($userId) failed: $e\n$st',
      );
    }
  }

  Future<void> _loadMorePosts(String userId, UserProfileState current) async {
    if (current.posts.loading || !current.posts.hasMore) return;
    state = AsyncData(
      current.copyWith(posts: current.posts.copyWith(loading: true)),
    );
    try {
      final next = current.posts.page + 1;
      final paged = await ref
          .read(userRepositoryProvider)
          .posts(userId, page: next);
      state = AsyncData(
        current.copyWith(
          posts: _PagedState<PostEntity>(
            list: [...current.posts.list, ...paged.list],
            page: next,
            hasMore: paged.hasMore,
          ),
        ),
      );
    } catch (_) {
      state = AsyncData(
        current.copyWith(posts: current.posts.copyWith(loading: false)),
      );
    }
  }

  Future<void> _loadMoreCollections(
    String userId,
    UserProfileState current,
  ) async {
    if (current.collections.loading || !current.collections.hasMore) return;
    state = AsyncData(
      current.copyWith(
        collections: current.collections.copyWith(loading: true),
      ),
    );
    try {
      final next = current.collections.page + 1;
      final paged = await ref
          .read(userRepositoryProvider)
          .collections(userId, page: next);
      state = AsyncData(
        current.copyWith(
          collections: _PagedState<PostEntity>(
            list: [...current.collections.list, ...paged.list],
            page: next,
            hasMore: paged.hasMore,
          ),
        ),
      );
    } catch (_) {
      state = AsyncData(
        current.copyWith(
          collections: current.collections.copyWith(loading: false),
        ),
      );
    }
  }

  Future<void> _loadLikes(String userId, UserProfileState current) async {
    try {
      final paged = await ref
          .read(userRepositoryProvider)
          .likes(userId, page: 1);
      state = AsyncData(
        current.copyWith(
          likes: _PagedState<PostEntity>(
            list: paged.list,
            hasMore: paged.hasMore,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('UserProfileController._loadLikes($userId) failed: $e\n$st');
    }
  }

  Future<void> _loadMoreLikes(String userId, UserProfileState current) async {
    if (current.likes.loading || !current.likes.hasMore) return;
    state = AsyncData(
      current.copyWith(likes: current.likes.copyWith(loading: true)),
    );
    try {
      final next = current.likes.page + 1;
      final paged = await ref
          .read(userRepositoryProvider)
          .likes(userId, page: next);
      state = AsyncData(
        current.copyWith(
          likes: _PagedState<PostEntity>(
            list: [...current.likes.list, ...paged.list],
            page: next,
            hasMore: paged.hasMore,
          ),
        ),
      );
    } catch (_) {
      state = AsyncData(
        current.copyWith(likes: current.likes.copyWith(loading: false)),
      );
    }
  }
}

final userProfileProvider =
    AsyncNotifierProvider.family<
      UserProfileController,
      UserProfileState,
      String
    >(UserProfileController.new);
