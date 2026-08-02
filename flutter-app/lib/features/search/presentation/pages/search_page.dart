import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/loading.dart';
import '../../../discover/presentation/widgets/post_card.dart';
import '../../application/search_controller.dart';
import '../widgets/search_user_card.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _SearchField(
          controller: _ctrl,
          onSubmit: (kw) =>
              ref.read(searchControllerProvider.notifier).search(keyword: kw),
          onChanged: (v) =>
              ref.read(searchControllerProvider.notifier).setKeyword(v),
        ),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final hasSearched = ref.watch(
                searchControllerProvider.select((s) => s.hasSearched),
              );
              return TextButton(
                onPressed: () {
                  if (hasSearched) {
                    ref.read(searchControllerProvider.notifier).reset();
                    _ctrl.clear();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
                child: Text(hasSearched ? l.commonSearch : l.commonCancel),
              );
            },
          ),
        ],
      ),
      body: Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(searchControllerProvider);
          return state.hasSearched
              ? _Results(state: state)
              : _Suggestions(state: state);
        },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onSubmit,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      margin: const EdgeInsets.only(left: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        keyboardType: TextInputType.text,
        onSubmitted: onSubmit,
        onChanged: onChanged,
        style: const TextStyle(fontSize: AppTextSize.body),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          prefixIcon: const Icon(Icons.search, size: 18),
          hintText: context.l10n.searchHint,
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.state});
  final SearchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (state.suggestions.isNotEmpty && state.keyword.trim().isNotEmpty) {
      return _SuggestionList(
        suggestions: state.suggestions,
        keyword: state.keyword,
        onTap: (kw) =>
            ref.read(searchControllerProvider.notifier).search(keyword: kw),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (state.history.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l.searchHistory,
                style: const TextStyle(
                  fontSize: AppTextSize.title,
                  fontWeight: FontWeight.w700,
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l.searchClearHistory),
                      content: Text(l.searchClearHistoryConfirm),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l.commonCancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l.commonConfirm),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await ref
                        .read(searchControllerProvider.notifier)
                        .clearHistory();
                    ref
                        .read(toastControllerProvider)
                        .success(l.searchHistoryCleared);
                  }
                },
                child: Text(
                  l.searchClearHistory,
                  style: const TextStyle(
                    fontSize: AppTextSize.caption,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: state.history
                .map(
                  (kw) => Chip(
                    label: Text(kw),
                    onDeleted: () => ref
                        .read(searchControllerProvider.notifier)
                        .removeHistory(kw),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        if (state.hot.isNotEmpty) ...[
          Text(
            l.searchHot,
            style: const TextStyle(
              fontSize: AppTextSize.title,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: state.hot
                .map(
                  (kw) => ActionChip(
                    label: Text(kw),
                    onPressed: () {
                      ref
                          .read(searchControllerProvider.notifier)
                          .search(keyword: kw);
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.suggestions,
    required this.keyword,
    required this.onTap,
  });

  final List<String> suggestions;
  final String keyword;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: suggestions.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: AppSpacing.xl + AppSpacing.lg,
        color: colors.outlineVariant.withValues(alpha: 0.3),
      ),
      itemBuilder: (ctx, i) {
        final suggestion = suggestions[i];
        return ListTile(
          leading: Icon(Icons.search, size: 18, color: colors.outline),
          title: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: _highlight(suggestion, keyword, colors),
          ),
          trailing: Icon(Icons.north_west, size: 14, color: colors.outline),
          onTap: () => onTap(suggestion),
        );
      },
    );
  }

  TextSpan _highlight(String text, String kw, ColorScheme colors) {
    final lower = text.toLowerCase();
    final kwLower = kw.toLowerCase();
    final idx = lower.indexOf(kwLower);
    if (idx < 0) {
      return TextSpan(
        text: text,
        style: TextStyle(fontSize: AppTextSize.body, color: colors.onSurface),
      );
    }
    return TextSpan(
      children: [
        if (idx > 0)
          TextSpan(
            text: text.substring(0, idx),
            style: TextStyle(
              fontSize: AppTextSize.body,
              color: colors.onSurface,
            ),
          ),
        TextSpan(
          text: text.substring(idx, idx + kw.length),
          style: TextStyle(
            fontSize: AppTextSize.body,
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (idx + kw.length < text.length)
          TextSpan(
            text: text.substring(idx + kw.length),
            style: TextStyle(
              fontSize: AppTextSize.body,
              color: colors.onSurface,
            ),
          ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.state});
  final SearchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Column(
      children: [
        Row(
          children: [
            _TabButton(
              label: l.searchResultPosts,
              selected: state.activeTab == SearchTab.posts,
              onTap: () => ref
                  .read(searchControllerProvider.notifier)
                  .switchTab(SearchTab.posts),
            ),
            _TabButton(
              label: l.searchResultUsers,
              selected: state.activeTab == SearchTab.users,
              onTap: () => ref
                  .read(searchControllerProvider.notifier)
                  .switchTab(SearchTab.users),
            ),
          ],
        ),
        Divider(height: 1, color: Theme.of(context).dividerColor),
        Expanded(
          child: state.loading
              ? const LoadingSpinner()
              : state.activeTab == SearchTab.posts
              ? _PostsList(state: state)
              : _UsersList(state: state),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppTextSize.body,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected
                  ? AppColors.primary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _PostsList extends ConsumerWidget {
  const _PostsList({required this.state});
  final SearchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = state.posts;
    if (posts.list.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        message: context.l10n.searchEmpty,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.66,
      ),
      itemCount: posts.list.length + (posts.hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i >= posts.list.length) {
          Future.microtask(
            () => ref.read(searchControllerProvider.notifier).loadMore(),
          );
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return PostCard(post: posts.list[i]);
      },
    );
  }
}

class _UsersList extends ConsumerWidget {
  const _UsersList({required this.state});
  final SearchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = state.users;
    if (users.list.isEmpty) {
      return EmptyState(
        icon: Icons.person_search_outlined,
        message: context.l10n.searchEmpty,
      );
    }
    return ListView.separated(
      itemCount: users.list.length + (users.hasMore ? 1 : 0),
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Theme.of(context).dividerColor),
      itemBuilder: (ctx, i) {
        if (i >= users.list.length) {
          Future.microtask(
            () => ref.read(searchControllerProvider.notifier).loadMore(),
          );
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return SearchUserCard(
          user: users.list[i],
          keyword: state.keyword,
          onTap: () => context.push('/user/${users.list[i].userId}'),
        );
      },
    );
  }
}
