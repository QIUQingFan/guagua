import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_data.dart';
import '../../../shared/domain/post_entity.dart';
import '../../../shared/domain/user_entity.dart';
import '../../../shared/providers/core_providers.dart';
import '../../post/data/post_repository.dart';
import '../../user/data/user_repository.dart';

enum SearchTab { posts, users }

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

class SearchState {
  const SearchState({
    this.keyword = '',
    this.hasSearched = false,
    this.activeTab = SearchTab.posts,
    this.posts = const _PagedState<PostEntity>(),
    this.users = const _PagedState<UserEntity>(),
    this.history = const [],
    this.hot = const [],
    this.loading = false,
    this.suggestions = const [],
  });

  final String keyword;
  final bool hasSearched;
  final SearchTab activeTab;
  final _PagedState<PostEntity> posts;
  final _PagedState<UserEntity> users;
  final List<String> history;
  final List<String> hot;
  final bool loading;

  final List<String> suggestions;

  SearchState copyWith({
    String? keyword,
    bool? hasSearched,
    SearchTab? activeTab,
    _PagedState<PostEntity>? posts,
    _PagedState<UserEntity>? users,
    List<String>? history,
    List<String>? hot,
    bool? loading,
    List<String>? suggestions,
  }) {
    return SearchState(
      keyword: keyword ?? this.keyword,
      hasSearched: hasSearched ?? this.hasSearched,
      activeTab: activeTab ?? this.activeTab,
      posts: posts ?? this.posts,
      users: users ?? this.users,
      history: history ?? this.history,
      hot: hot ?? this.hot,
      loading: loading ?? this.loading,
      suggestions: suggestions ?? this.suggestions,
    );
  }
}

class SearchController extends Notifier<SearchState> {
  Timer? _debounce;

  @override
  SearchState build() {
    ref.onDispose(() => _debounce?.cancel());
    _init();
    return const SearchState();
  }

  void _init() async {
    final prefs = ref.read(sharedPrefsStorageProvider);
    if (prefs != null) {
      state = state.copyWith(history: prefs.getSearchHistory());
    }
    try {
      final hot = await ref.read(postRepositoryProvider).hotTags();
      state = state.copyWith(hot: hot);
    } catch (_) {}
  }

  void setKeyword(String kw) {
    state = state.copyWith(keyword: kw);
    _debounce?.cancel();
    if (kw.trim().isEmpty) {
      state = state.copyWith(suggestions: const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _generateSuggestions(kw.trim());
    });
  }

  void _generateSuggestions(String kw) {
    final lower = kw.toLowerCase();
    final fromHistory = state.history
        .where((h) => h.toLowerCase().contains(lower))
        .take(5)
        .toList();
    final fromHot = state.hot
        .where((h) => h.toLowerCase().contains(lower))
        .take(5)
        .toList();
    final merged = <String>[...fromHistory];
    for (final h in fromHot) {
      if (!merged.contains(h)) merged.add(h);
    }
    state = state.copyWith(suggestions: merged.take(8).toList());
  }

  Future<void> search({String? keyword}) async {
    final kw = (keyword ?? state.keyword).trim();
    if (kw.isEmpty) return;
    state = state.copyWith(
      keyword: kw,
      hasSearched: true,
      loading: true,
      posts: const _PagedState<PostEntity>(),
      users: const _PagedState<UserEntity>(),
    );

    final prefs = ref.read(sharedPrefsStorageProvider);
    if (prefs != null) {
      await prefs.addSearchHistory(kw);
      state = state.copyWith(history: prefs.getSearchHistory());
    }

    try {
      final results = await Future.wait([
        ref.read(postRepositoryProvider).search(keyword: kw, page: 1),
        ref.read(userRepositoryProvider).search(keyword: kw, page: 1),
      ]);
      state = state.copyWith(
        loading: false,
        posts: _PagedState<PostEntity>(
          list: (results[0] as PagedData<PostEntity>).list,
          hasMore: (results[0] as PagedData<PostEntity>).hasMore,
        ),
        users: _PagedState<UserEntity>(
          list: (results[1] as PagedData<UserEntity>).list,
          hasMore: (results[1] as PagedData<UserEntity>).hasMore,
        ),
      );
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  void switchTab(SearchTab tab) => state = state.copyWith(activeTab: tab);

  Future<void> loadMore() async {
    final tab = state.activeTab;
    if (tab == SearchTab.posts) {
      if (state.posts.loading || !state.posts.hasMore) return;
      state = state.copyWith(posts: state.posts.copyWith(loading: true));
      try {
        final next = state.posts.page + 1;
        final paged = await ref
            .read(postRepositoryProvider)
            .search(keyword: state.keyword, page: next);
        state = state.copyWith(
          posts: _PagedState<PostEntity>(
            list: [...state.posts.list, ...paged.list],
            page: next,
            hasMore: paged.hasMore,
          ),
        );
      } catch (_) {
        state = state.copyWith(posts: state.posts.copyWith(loading: false));
      }
    } else {
      if (state.users.loading || !state.users.hasMore) return;
      state = state.copyWith(users: state.users.copyWith(loading: true));
      try {
        final next = state.users.page + 1;
        final paged = await ref
            .read(userRepositoryProvider)
            .search(keyword: state.keyword, page: next);
        state = state.copyWith(
          users: _PagedState<UserEntity>(
            list: [...state.users.list, ...paged.list],
            page: next,
            hasMore: paged.hasMore,
          ),
        );
      } catch (_) {
        state = state.copyWith(users: state.users.copyWith(loading: false));
      }
    }
  }

  Future<void> removeHistory(String kw) async {
    final prefs = ref.read(sharedPrefsStorageProvider);
    if (prefs == null) return;
    await prefs.removeSearchHistory(kw);
    state = state.copyWith(history: prefs.getSearchHistory());
  }

  Future<void> clearHistory() async {
    final prefs = ref.read(sharedPrefsStorageProvider);
    if (prefs == null) return;
    await prefs.clearSearchHistory();
    state = state.copyWith(history: const []);
  }

  void reset() {
    state = SearchState(history: state.history, hot: state.hot);
  }
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);
