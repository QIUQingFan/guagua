import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exceptions.dart';
import '../data/shop_repository.dart';
import '../domain/shop_entities.dart';

final productCategoriesProvider = FutureProvider<List<ProductCategoryEntity>>(
  (ref) async => ref.watch(productRepositoryProvider).categories(),
);

class ProductListState {
  const ProductListState({
    this.categoryId,
    this.keyword,
    this.sort,
    this.list = const [],
    this.page = 1,
    this.hasMore = true,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  final int? categoryId;
  final String? keyword;
  final String? sort;
  final List<ProductEntity> list;
  final int page;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final Object? error;

  bool get isEmpty => list.isEmpty && !loading;
  bool get hasError => error != null;

  ProductListState copyWith({
    int? categoryId,
    String? keyword,
    String? sort,
    List<ProductEntity>? list,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
    bool clearCategory = false,
    bool clearKeyword = false,
  }) {
    return ProductListState(
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      keyword: clearKeyword ? null : (keyword ?? this.keyword),
      sort: sort ?? this.sort,
      list: list ?? this.list,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ProductListController extends Notifier<ProductListState> {
  @override
  ProductListState build() {
    Future.microtask(refresh);
    return const ProductListState(loading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final paged = await ref
          .read(productRepositoryProvider)
          .list(
            categoryId: state.categoryId,
            keyword: state.keyword,
            sort: state.sort,
            page: 1,
          );
      state = ProductListState(
        categoryId: state.categoryId,
        keyword: state.keyword,
        sort: state.sort,
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
      final nextPage = state.page + 1;
      final paged = await ref
          .read(productRepositoryProvider)
          .list(
            categoryId: state.categoryId,
            keyword: state.keyword,
            sort: state.sort,
            page: nextPage,
          );
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

  Future<void> switchCategory(int? categoryId) async {
    state = ProductListState(
      categoryId: categoryId,
      sort: state.sort,
      loading: true,
    );
    await refresh();
  }

  Future<void> setSort(String? sort) async {
    state = state.copyWith(sort: sort, loading: true);
    await refresh();
  }

  Future<void> search(String keyword) async {
    state = ProductListState(keyword: keyword, loading: true);
    try {
      final paged = await ref
          .read(productRepositoryProvider)
          .search(keyword: keyword, page: 1);
      state = ProductListState(
        keyword: keyword,
        list: paged.list,
        page: 1,
        hasMore: paged.hasMore,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }
}

final productListControllerProvider =
    NotifierProvider<ProductListController, ProductListState>(
      ProductListController.new,
    );

final productDetailProvider = FutureProvider.family<ProductEntity, int>((
  ref,
  id,
) async {
  return ref.watch(productRepositoryProvider).detail(id);
});

/// 相关推荐：根据当前商品 ID 拉取同类目热门商品（去重当前商品）。
final relatedProductsProvider = FutureProvider.family<List<ProductEntity>, int>(
  (ref, id) async {
    final repo = ref.watch(productRepositoryProvider);
    final detail = await repo.detail(id);
    final paged = await repo.list(
      categoryId: detail.categoryId,
      page: 1,
      limit: 10,
    );
    return paged.list.where((p) => p.id != id).toList();
  },
);

/// 热门推荐：全局热门商品（用于详情页底部"你可能喜欢"区块）。
final hotProductsProvider = FutureProvider<List<ProductEntity>>((ref) async {
  return ref.watch(productRepositoryProvider).recommend(type: 'hot');
});

class CartController extends AsyncNotifier<CartEntity> {
  @override
  Future<CartEntity> build() async {
    return ref.read(cartRepositoryProvider).fetch();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(cartRepositoryProvider).fetch(),
    );
  }

  Future<void> add(int productId, int quantity, {String? spec}) async {
    await ref.read(cartRepositoryProvider).add(productId, quantity, spec: spec);
    ref.invalidateSelf();
  }

  /// 乐观更新勾选状态。
  Future<void> toggleSelect(int itemId, bool selected) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.toggleItem(itemId, selected));
    try {
      await ref.read(cartRepositoryProvider).updateSelect(itemId, selected);
    } catch (_) {
      state = AsyncData(current.toggleItem(itemId, !selected));
    }
  }

  /// 乐观更新全选。
  Future<void> toggleSelectAll(bool selected) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.toggleAll(selected));
    for (final item in current.items) {
      if (item.selected != selected) {
        try {
          await ref
              .read(cartRepositoryProvider)
              .updateSelect(item.id, selected);
        } catch (_) {
        }
      }
    }
  }

  /// 乐观更新数量。
  Future<void> updateQuantity(int itemId, int quantity) async {
    if (quantity < 1) return;
    final current = state.valueOrNull;
    if (current == null) return;
    final oldQuantity = current.items
        .firstWhere((i) => i.id == itemId)
        .quantity;
    state = AsyncData(current.updateQuantity(itemId, quantity));
    try {
      await ref.read(cartRepositoryProvider).updateQuantity(itemId, quantity);
    } catch (_) {
      state = AsyncData(current.updateQuantity(itemId, oldQuantity));
    }
  }

  /// 删除购物车项。
  Future<void> remove(int itemId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.removeItem(itemId));
    try {
      await ref.read(cartRepositoryProvider).remove(itemId);
    } catch (_) {
      ref.invalidateSelf();
    }
  }

  /// 清空已选（下单成功后调用）。
  Future<void> clearSelected() async {
    try {
      await ref.read(cartRepositoryProvider).clearSelected();
      ref.invalidateSelf();
    } catch (_) {
    }
  }
}

final cartControllerProvider =
    AsyncNotifierProvider<CartController, CartEntity>(CartController.new);

/// 派生：购物车已选数量（用于底部导航红点）。
final cartSelectedCountProvider = Provider<int>((ref) {
  final cart = ref.watch(cartControllerProvider).valueOrNull;
  return cart?.items.where((i) => i.selected).length ?? 0;
});

/// 派生：购物车总数量（用于底部导航红点）。
final cartCountProvider = Provider<int>((ref) {
  final cart = ref.watch(cartControllerProvider).valueOrNull;
  return cart?.items.length ?? 0;
});

class OrderListState {
  const OrderListState({
    this.status,
    this.list = const [],
    this.page = 1,
    this.hasMore = true,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  final String? status;
  final List<OrderEntity> list;
  final int page;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final Object? error;

  bool get isEmpty => list.isEmpty && !loading;

  OrderListState copyWith({
    String? status,
    List<OrderEntity>? list,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
    bool clearStatus = false,
  }) {
    return OrderListState(
      status: clearStatus ? null : (status ?? this.status),
      list: list ?? this.list,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class OrderListController extends Notifier<OrderListState> {
  @override
  OrderListState build() {
    Future.microtask(refresh);
    return const OrderListState(loading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final paged = await ref
          .read(orderRepositoryProvider)
          .list(status: state.status, page: 1);
      state = OrderListState(
        status: state.status,
        list: paged.list,
        page: 1,
        hasMore: paged.hasMore,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.loading) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final nextPage = state.page + 1;
      final paged = await ref
          .read(orderRepositoryProvider)
          .list(status: state.status, page: nextPage);
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

  Future<void> switchStatus(String? status) async {
    state = OrderListState(status: status, loading: true);
    await refresh();
  }

  Future<bool> cancel(int orderId) async {
    try {
      await ref.read(orderRepositoryProvider).cancel(orderId);
      final list = state.list.map((o) {
        if (o.id == orderId) {
          return OrderEntity(
            id: o.id,
            orderNo: o.orderNo,
            status: OrderStatus.cancelled,
            items: o.items,
            totalAmount: o.totalAmount,
            createdAt: o.createdAt,
            addressName: o.addressName,
            addressPhone: o.addressPhone,
            addressDetail: o.addressDetail,
            remark: o.remark,
            updatedAt: DateTime.now(),
            statusLogs: o.statusLogs,
          );
        }
        return o;
      }).toList();
      state = state.copyWith(list: list);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> confirm(int orderId) async {
    try {
      await ref.read(orderRepositoryProvider).confirm(orderId);
      final list = state.list.map((o) {
        if (o.id == orderId) {
          return OrderEntity(
            id: o.id,
            orderNo: o.orderNo,
            status: OrderStatus.completed,
            items: o.items,
            totalAmount: o.totalAmount,
            createdAt: o.createdAt,
            addressName: o.addressName,
            addressPhone: o.addressPhone,
            addressDetail: o.addressDetail,
            remark: o.remark,
            updatedAt: DateTime.now(),
            statusLogs: o.statusLogs,
          );
        }
        return o;
      }).toList();
      state = state.copyWith(list: list);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final orderListControllerProvider =
    NotifierProvider<OrderListController, OrderListState>(
      OrderListController.new,
    );

final orderDetailProvider = FutureProvider.family<OrderEntity, int>((
  ref,
  id,
) async {
  return ref.watch(orderRepositoryProvider).detail(id);
});

/// 下单控制器：临时状态，存放结算页选中的商品与地址。
class CheckoutState {
  const CheckoutState({
    this.items = const [],
    this.addressId,
    this.remark,
    this.placing = false,
    this.placedOrderId,
    this.error,
  });

  final List<CreateOrderItem> items;
  final int? addressId;
  final String? remark;
  final bool placing;
  final int? placedOrderId;
  final Object? error;

  CheckoutState copyWith({
    List<CreateOrderItem>? items,
    int? addressId,
    String? remark,
    bool? placing,
    int? placedOrderId,
    Object? error,
    bool clearError = false,
    bool clearPlaced = false,
  }) {
    return CheckoutState(
      items: items ?? this.items,
      addressId: addressId ?? this.addressId,
      remark: remark ?? this.remark,
      placing: placing ?? this.placing,
      placedOrderId: clearPlaced ? null : (placedOrderId ?? this.placedOrderId),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class CheckoutController extends Notifier<CheckoutState> {
  @override
  CheckoutState build() => const CheckoutState();

  void setItems(List<CreateOrderItem> items) {
    state = state.copyWith(items: items, clearPlaced: true, clearError: true);
  }

  void setAddress(int? addressId) {
    state = state.copyWith(addressId: addressId, clearError: true);
  }

  void setRemark(String? remark) {
    state = state.copyWith(remark: remark);
  }

  Future<void> placeOrder() async {
    if (state.placing) return;
    if (state.items.isEmpty || state.addressId == null) {
      state = state.copyWith(error: 'invalid_input');
      return;
    }
    state = state.copyWith(placing: true, clearError: true, clearPlaced: true);
    try {
      final order = await ref
          .read(orderRepositoryProvider)
          .create(
            items: state.items,
            addressId: state.addressId!,
            remark: state.remark,
          );
      await ref.read(cartControllerProvider.notifier).clearSelected();
      state = state.copyWith(placing: false, placedOrderId: order.id);
    } catch (e) {
      state = state.copyWith(placing: false, error: e);
    }
  }
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);

class AddressListState {
  const AddressListState({
    this.list = const [],
    this.loading = false,
    this.error,
  });

  final List<AddressEntity> list;
  final bool loading;
  final Object? error;

  AddressListState copyWith({
    List<AddressEntity>? list,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) {
    return AddressListState(
      list: list ?? this.list,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AddressListController extends Notifier<AddressListState> {
  @override
  AddressListState build() {
    Future.microtask(refresh);
    return const AddressListState(loading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final list = await ref.read(addressRepositoryProvider).list();
      state = AddressListState(list: list);
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<bool> save(SaveAddressRequest req) async {
    try {
      await ref.read(addressRepositoryProvider).save(req);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> remove(int id) async {
    try {
      await ref.read(addressRepositoryProvider).remove(id);
      final list = state.list.where((a) => a.id != id).toList();
      state = state.copyWith(list: list);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final addressListControllerProvider =
    NotifierProvider<AddressListController, AddressListState>(
      AddressListController.new,
    );

/// 派生：默认地址。
final defaultAddressProvider = Provider<AddressEntity?>((ref) {
  final list = ref.watch(addressListControllerProvider).list;
  for (final a in list) {
    if (a.isDefault) return a;
  }
  return list.isEmpty ? null : list.first;
});
