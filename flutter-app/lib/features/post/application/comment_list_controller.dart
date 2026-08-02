import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/comment_entity.dart';
import '../../auth/application/auth_controller.dart';
import '../data/post_repository.dart';

class CommentListState {
  const CommentListState({
    this.list = const [],
    this.page = 1,
    this.hasMore = true,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  final List<CommentEntity> list;
  final int page;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final Object? error;

  bool get isEmpty => list.isEmpty && !loading;
  bool get hasError => error != null;

  CommentListState copyWith({
    List<CommentEntity>? list,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
  }) {
    return CommentListState(
      list: list ?? this.list,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class CommentListController extends FamilyNotifier<CommentListState, int> {
  @override
  CommentListState build(int postId) {
    Future.microtask(() => refresh(postId));
    return const CommentListState(loading: true);
  }

  Future<void> refresh(int postId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final paged = await ref
          .read(postRepositoryProvider)
          .comments(postId, page: 1);
      state = CommentListState(
        list: paged.list,
        page: 1,
        hasMore: paged.hasMore,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore(int postId) async {
    if (state.loadingMore || !state.hasMore || state.loading) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final next = state.page + 1;
      final paged = await ref
          .read(postRepositoryProvider)
          .comments(postId, page: next);
      state = state.copyWith(
        list: [...state.list, ...paged.list],
        page: next,
        hasMore: paged.hasMore,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }

  Future<bool> publish(
    int postId, {
    required String content,
    int? parentId,
  }) async {
    try {
      final entity = await ref
          .read(postRepositoryProvider)
          .createComment(postId, content: content, parentId: parentId);
      final me = ref.read(currentUserProvider);
      final enriched = me == null
          ? entity
          : entity.copyWith(
              authorId: entity.authorId == 0 ? me.id : entity.authorId,
              authorNickname: entity.authorNickname.isEmpty
                  ? me.nickname
                  : entity.authorNickname,
              authorUserId: entity.authorUserId.isEmpty
                  ? me.userId
                  : entity.authorUserId,
              authorAvatar: entity.authorAvatar.isEmpty
                  ? me.avatar
                  : entity.authorAvatar,
              authorVerified: me.isVerified,
            );

      if (parentId != null) {
        final newList = state.list.map((c) {
          if (c.id == parentId) {
            return c.copyWith(replyCount: c.replyCount + 1);
          }
          return c;
        }).toList();
        final curReplies = _replies[parentId] ?? const <CommentEntity>[];
        _replies[parentId] = [enriched, ...curReplies];
        state = state.copyWith(list: newList);
      } else {
        state = state.copyWith(list: [enriched, ...state.list]);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  final Map<int, List<CommentEntity>> _replies = {};

  bool repliesLoaded(int parentId) => _replies.containsKey(parentId);

  List<CommentEntity> repliesOf(int parentId) => _replies[parentId] ?? const [];

  Future<void> loadReplies(int parentId) async {
    if (_replies.containsKey(parentId)) return;
    try {
      final paged = await ref.read(postRepositoryProvider).replies(parentId);
      _replies[parentId] = paged.list;
      state = state.copyWith();
    } catch (_) {}
  }

  Future<void> delete(int commentId) async {
    final prev = state.list;
    state = state.copyWith(list: prev.where((c) => c.id != commentId).toList());
    try {
      await ref.read(postRepositoryProvider).deleteComment(commentId);
    } catch (_) {
      state = state.copyWith(list: prev);
    }
  }

  Future<void> toggleLike(int commentId) async {
    final comment = _findComment(commentId);
    if (comment == null) return;
    final prevList = state.list;
    final prevReplies = Map<int, List<CommentEntity>>.from(_replies);

    final updated = comment.copyWith(
      liked: !comment.liked,
      likeCount: comment.liked ? comment.likeCount - 1 : comment.likeCount + 1,
    );
    _updateComment(updated);
    state = state.copyWith();

    try {
      final repo = ref.read(postRepositoryProvider);
      if (comment.liked) {
        await repo.unlikeComment(commentId);
      } else {
        await repo.likeComment(commentId);
      }
    } catch (_) {
      _replies
        ..clear()
        ..addAll(prevReplies);
      state = state.copyWith(list: prevList);
    }
  }

  CommentEntity? _findComment(int commentId) {
    for (final c in state.list) {
      if (c.id == commentId) return c;
    }
    for (final entry in _replies.entries) {
      for (final r in entry.value) {
        if (r.id == commentId) return r;
      }
    }
    return null;
  }

  void _updateComment(CommentEntity updated) {
    final newList = state.list.map((c) {
      return c.id == updated.id ? updated : c;
    }).toList();
    state = state.copyWith(list: newList);
    for (final entry in _replies.entries) {
      final reps = entry.value.map((r) {
        return r.id == updated.id ? updated : r;
      }).toList();
      _replies[entry.key] = reps;
    }
  }
}

final commentListProvider =
    NotifierProvider.family<CommentListController, CommentListState, int>(
      CommentListController.new,
    );
