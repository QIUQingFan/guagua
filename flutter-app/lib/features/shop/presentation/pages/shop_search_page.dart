import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry.dart';
import '../../application/shop_controllers.dart';
import '../../domain/shop_entities.dart';

/// 商品搜索页：关键字搜索 + 结果列表 + 历史记录。
class ShopSearchPage extends ConsumerStatefulWidget {
  const ShopSearchPage({super.key});

  @override
  ConsumerState<ShopSearchPage> createState() => _ShopSearchPageState();
}

class _ShopSearchPageState extends ConsumerState<ShopSearchPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _hasSearched = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _doSearch(String kw) {
    final keyword = kw.trim();
    if (keyword.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _hasSearched = true);
    ref.read(productListControllerProvider.notifier).search(keyword);
  }

  void _reset() {
    setState(() => _hasSearched = false);
    _ctrl.clear();
    ref.read(productListControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _SearchField(
          controller: _ctrl,
          focusNode: _focus,
          onSubmit: _doSearch,
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (_hasSearched) {
                _reset();
              } else {
                Navigator.of(context).pop();
              }
            },
            child: Text(_hasSearched ? l.commonSearch : l.commonCancel),
          ),
        ],
      ),
      body: _hasSearched
          ? _SearchResults()
          : _SearchSuggestions(onPick: _doSearch, controller: _ctrl),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmit;

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
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        keyboardType: TextInputType.text,
        onSubmitted: onSubmit,
        style: const TextStyle(fontSize: AppTextSize.body),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          prefixIcon: const Icon(Icons.search, size: 18),
          hintText: context.l10n.shopSearchHint,
          border: InputBorder.none,
        ),
      ),
    );
  }
}

/// 搜索建议（历史 + 热门商品分类作为快捷入口）。
class _SearchSuggestions extends ConsumerStatefulWidget {
  const _SearchSuggestions({required this.onPick, required this.controller});

  final ValueChanged<String> onPick;
  final TextEditingController controller;

  @override
  ConsumerState<_SearchSuggestions> createState() => _SearchSuggestionsState();
}

class _SearchSuggestionsState extends ConsumerState<_SearchSuggestions> {
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final storage = ref.read(sharedPrefsStorageProvider);
    if (storage != null) {
      setState(() => _history = storage.getSearchHistory());
    }
  }

  Future<void> _clearHistory() async {
    final storage = ref.read(sharedPrefsStorageProvider);
    if (storage == null) return;
    await storage.clearSearchHistory();
    setState(() => _history = []);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (_history.isNotEmpty) ...[
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
                onTap: _clearHistory,
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
            children: _history
                .map(
                  (kw) => Chip(
                    label: Text(kw),
                    onDeleted: () async {
                      final storage = ref.read(sharedPrefsStorageProvider);
                      if (storage != null) {
                        await storage.removeSearchHistory(kw);
                        setState(() => _history = storage.getSearchHistory());
                      }
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        Text(
          '热门搜索',
          style: const TextStyle(
            fontSize: AppTextSize.title,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: ['手机', '电脑', '服饰', '食品', '家居', '美妆']
              .map(
                (kw) => ActionChip(
                  label: Text(kw),
                  onPressed: () {
                    widget.controller.text = kw;
                    widget.onPick(kw);
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

/// 搜索结果列表。
class _SearchResults extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(productListControllerProvider);
    final l = context.l10n;

    if (state.loading && state.list.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError && state.list.isEmpty) {
      return ErrorRetryView(
        message: l.commonNetworkError,
        onRetry: () => ref
            .read(productListControllerProvider.notifier)
            .search(state.keyword ?? ''),
      );
    }
    if (state.isEmpty) {
      return EmptyState(icon: Icons.search_off, message: '暂无搜索结果');
    }

    final keyword = state.keyword;
    if (keyword != null && keyword.isNotEmpty) {
      Future.microtask(() async {
        final storage = ref.read(sharedPrefsStorageProvider);
        if (storage != null) {
          await storage.addSearchHistory(keyword);
        }
      });
    }

    return RefreshIndicator(
      onRefresh: () => ref
          .read(productListControllerProvider.notifier)
          .search(keyword ?? ''),
      child: GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.sm),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 0.65,
        ),
        itemCount: state.list.length + (state.hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i >= state.list.length) {
            Future.microtask(
              () => ref.read(productListControllerProvider.notifier).loadMore(),
            );
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return _SearchProductCard(product: state.list[i]);
        },
      ),
    );
  }
}

/// 搜索结果商品卡片。
class _SearchProductCard extends StatelessWidget {
  const _SearchProductCard({required this.product});

  final ProductEntity product;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => context.push('/shop/product/${product.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: product.cover.isEmpty
                  ? Container(
                      color: colors.surfaceContainerHighest,
                      child: Icon(Icons.image_outlined, color: colors.outline),
                    )
                  : CachedNetworkImage(
                      imageUrl: product.cover,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: colors.surfaceContainerHighest),
                      errorWidget: (_, __, ___) => Container(
                        color: colors.surfaceContainerHighest,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: colors.outline,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${context.l10n.shopPriceSymbol}${product.price.toStringAsFixed(2)}',
                    style: tt.titleMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
