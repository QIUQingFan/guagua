import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_paths.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/paged_data.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/shop_entities.dart';
import 'shop_dtos.dart';

export 'shop_dtos.dart'
    show
        AddToCartRequest,
        CreateOrderItem,
        CreateOrderRequest,
        SaveAddressRequest;

class ProductApi {
  const ProductApi(this._client);
  final DioClient _client;

  /// 分类树：`GET /api/products/categories`。
  Future<List<ProductCategoryDto>> categories() async {
    final raw = await _client.get(
      ApiPaths.productsCategories,
      decode: (d) => d,
    );
    final list = raw is List
        ? raw
        : (raw is Map
              ? raw['categories'] ?? const <dynamic>[]
              : const <dynamic>[]);
    return (list as List<dynamic>)
        .map((e) => ProductCategoryDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 商品列表：`GET /api/products`。
  Future<PagedData<ProductDto>> list({
    int? categoryId,
    String? keyword,
    String? sort,
    int page = 1,
    int limit = 20,
  }) {
    return _client.getPaged(
      ApiPaths.products,
      query: {
        if (categoryId != null) 'category_id': categoryId,
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
        if (sort != null) 'sort': sort,
        'page': page,
        'limit': limit,
      },
      listKey: 'products',
      decode: ProductDto.fromJson,
    );
  }

  /// 商品详情：`GET /api/products/:id`。
  Future<ProductDto> detail(int id) {
    return _client.get(
      ApiPaths.product(id),
      decode: (d) => ProductDto.fromJson(d as Map<String, dynamic>),
    );
  }

  /// 商品搜索：`GET /api/products/search`。
  ///
  /// 当后端返回 404（商品不存在）时，视为空结果而非网络错误。
  Future<PagedData<ProductDto>> search({
    required String keyword,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      return await _client.getPaged(
        ApiPaths.productsSearch,
        query: {'keyword': keyword, 'page': page, 'limit': limit},
        listKey: 'products',
        decode: ProductDto.fromJson,
      );
    } on ApiException catch (e) {
      if (e.code == 404 || e.isNotFound) {
        return PagedData<ProductDto>(
          list: const [],
          total: 0,
          page: page,
          limit: limit,
          hasMore: false,
        );
      }
      rethrow;
    }
  }

  /// 推荐：`GET /api/products/recommend`。
  Future<List<ProductDto>> recommend({String? type}) async {
    final raw = await _client.get(
      ApiPaths.productsRecommend,
      query: {if (type != null) 'type': type},
      decode: (d) => d,
    );
    final list = raw is List
        ? raw
        : (raw is Map
              ? raw['products'] ?? const <dynamic>[]
              : const <dynamic>[]);
    return (list as List<dynamic>)
        .map((e) => ProductDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class CartApi {
  const CartApi(this._client);
  final DioClient _client;

  /// 购物车列表：`GET /api/cart`。
  Future<List<CartItemDto>> list() async {
    final raw = await _client.get(ApiPaths.cart, decode: (d) => d);
    final list = raw is List
        ? raw
        : (raw is Map
              ? raw['items'] ?? raw['cart'] ?? const <dynamic>[]
              : const <dynamic>[]);
    return (list as List<dynamic>)
        .map((e) => CartItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 加入购物车：`POST /api/cart`。
  Future<CartItemDto> add(AddToCartRequest req) {
    return _client.post(
      ApiPaths.cart,
      data: req.toJson(),
      decode: (d) => CartItemDto.fromJson(d as Map<String, dynamic>),
    );
  }

  /// 改量：`PUT /api/cart/:itemId`。
  Future<void> updateQuantity(int itemId, int quantity) =>
      _client.putVoid(ApiPaths.cartItem(itemId), data: {'quantity': quantity});

  /// 勾选：`PUT /api/cart/:itemId/select`。
  Future<void> updateSelect(int itemId, bool selected) => _client.putVoid(
    ApiPaths.cartItemSelect(itemId),
    data: {'selected': selected},
  );

  /// 删除：`DELETE /api/cart/:itemId`。
  Future<void> remove(int itemId) =>
      _client.deleteVoid(ApiPaths.cartItem(itemId));

  /// 清空已选：`POST /api/cart/clear-selected`。
  Future<void> clearSelected() => _client.postVoid(ApiPaths.cartClearSelected);
}

class OrderApi {
  const OrderApi(this._client);
  final DioClient _client;

  /// 下单：`POST /api/orders`。
  Future<OrderDto> create(CreateOrderRequest req) {
    return _client.post(
      ApiPaths.orders,
      data: req.toJson(),
      decode: (d) => OrderDto.fromJson(d as Map<String, dynamic>),
    );
  }

  /// 订单列表：`GET /api/orders`。
  Future<PagedData<OrderDto>> list({
    String? status,
    int page = 1,
    int limit = 20,
  }) {
    return _client.getPaged(
      ApiPaths.orders,
      query: {
        if (status != null) 'status': status,
        'page': page,
        'limit': limit,
      },
      listKey: 'orders',
      decode: OrderDto.fromJson,
    );
  }

  /// 订单详情：`GET /api/orders/:id`。
  Future<OrderDto> detail(int id) {
    return _client.get(
      ApiPaths.order(id),
      decode: (d) => OrderDto.fromJson(d as Map<String, dynamic>),
    );
  }

  /// 取消订单：`POST /api/orders/:id/cancel`。
  Future<void> cancel(int id) => _client.postVoid(ApiPaths.orderCancel(id));

  /// 确认收货：`POST /api/orders/:id/confirm`。
  Future<void> confirm(int id) => _client.postVoid(ApiPaths.orderConfirm(id));
}

class AddressApi {
  const AddressApi(this._client);
  final DioClient _client;

  /// 地址列表：`GET /api/addresses`。
  Future<List<AddressDto>> list() async {
    final raw = await _client.get(ApiPaths.addresses, decode: (d) => d);
    final list = raw is List
        ? raw
        : (raw is Map
              ? raw['addresses'] ?? raw['list'] ?? const <dynamic>[]
              : const <dynamic>[]);
    return (list as List<dynamic>)
        .map((e) => AddressDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 新增：`POST /api/addresses`。
  Future<AddressDto> create(SaveAddressRequest req) {
    return _client.post(
      ApiPaths.addresses,
      data: req.toJson(),
      decode: (d) => AddressDto.fromJson(d as Map<String, dynamic>),
    );
  }

  /// 更新：`PUT /api/addresses/:id`。
  Future<AddressDto> update(int id, SaveAddressRequest req) {
    return _client.put(
      ApiPaths.address(id),
      data: req.toJson(),
      decode: (d) => AddressDto.fromJson(d as Map<String, dynamic>),
    );
  }

  /// 删除：`DELETE /api/addresses/:id`。
  Future<void> remove(int id) => _client.deleteVoid(ApiPaths.address(id));
}

class ProductRepository {
  const ProductRepository(this._api);
  final ProductApi _api;

  Future<List<ProductCategoryEntity>> categories() async {
    final list = await _api.categories();
    return list.map((e) => e.toEntity()).toList();
  }

  Future<PagedData<ProductEntity>> list({
    int? categoryId,
    String? keyword,
    String? sort,
    int page = 1,
    int limit = 20,
  }) async {
    final paged = await _api.list(
      categoryId: categoryId,
      keyword: keyword,
      sort: sort,
      page: page,
      limit: limit,
    );
    return _mapPaged(paged, (e) => e.toEntity());
  }

  Future<ProductEntity> detail(int id) async =>
      (await _api.detail(id)).toEntity();

  Future<PagedData<ProductEntity>> search({
    required String keyword,
    int page = 1,
    int limit = 20,
  }) async {
    final paged = await _api.search(keyword: keyword, page: page, limit: limit);
    return _mapPaged(paged, (e) => e.toEntity());
  }

  Future<List<ProductEntity>> recommend({String? type}) async {
    final list = await _api.recommend(type: type);
    return list.map((e) => e.toEntity()).toList();
  }
}

class CartRepository {
  const CartRepository(this._api);
  final CartApi _api;

  Future<CartEntity> fetch() async {
    final list = await _api.list();
    return CartEntity(items: list.map((e) => e.toEntity()).toList());
  }

  Future<CartItemEntity> add(
    int productId,
    int quantity, {
    String? spec,
  }) async {
    final dto = await _api.add(
      AddToCartRequest(productId: productId, quantity: quantity, spec: spec),
    );
    return dto.toEntity();
  }

  Future<void> updateQuantity(int itemId, int quantity) =>
      _api.updateQuantity(itemId, quantity);

  Future<void> updateSelect(int itemId, bool selected) =>
      _api.updateSelect(itemId, selected);

  Future<void> remove(int itemId) => _api.remove(itemId);

  Future<void> clearSelected() => _api.clearSelected();
}

class OrderRepository {
  const OrderRepository(this._api);
  final OrderApi _api;

  Future<OrderEntity> create({
    required List<CreateOrderItem> items,
    required int addressId,
    String? remark,
  }) async {
    final dto = await _api.create(
      CreateOrderRequest(items: items, addressId: addressId, remark: remark),
    );
    return dto.toEntity();
  }

  Future<PagedData<OrderEntity>> list({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    final paged = await _api.list(status: status, page: page, limit: limit);
    return _mapPaged(paged, (e) => e.toEntity());
  }

  Future<OrderEntity> detail(int id) async =>
      (await _api.detail(id)).toEntity();

  Future<void> cancel(int id) => _api.cancel(id);

  Future<void> confirm(int id) => _api.confirm(id);
}

class AddressRepository {
  const AddressRepository(this._api);
  final AddressApi _api;

  Future<List<AddressEntity>> list() async {
    final list = await _api.list();
    return list.map((e) => e.toEntity()).toList();
  }

  Future<AddressEntity> save(SaveAddressRequest req) async {
    final dto = req.id == null
        ? await _api.create(req)
        : await _api.update(req.id!, req);
    return dto.toEntity();
  }

  Future<void> remove(int id) => _api.remove(id);
}

final productApiProvider = Provider<ProductApi>(
  (ref) => ProductApi(ref.watch(dioClientProvider)),
);
final cartApiProvider = Provider<CartApi>(
  (ref) => CartApi(ref.watch(dioClientProvider)),
);
final orderApiProvider = Provider<OrderApi>(
  (ref) => OrderApi(ref.watch(dioClientProvider)),
);
final addressApiProvider = Provider<AddressApi>(
  (ref) => AddressApi(ref.watch(dioClientProvider)),
);

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepository(ref.watch(productApiProvider)),
);
final cartRepositoryProvider = Provider<CartRepository>(
  (ref) => CartRepository(ref.watch(cartApiProvider)),
);
final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => OrderRepository(ref.watch(orderApiProvider)),
);
final addressRepositoryProvider = Provider<AddressRepository>(
  (ref) => AddressRepository(ref.watch(addressApiProvider)),
);

/// 通用分页转换辅助。
PagedData<T> _mapPaged<S, T>(PagedData<S> source, T Function(S) converter) {
  return PagedData<T>(
    list: source.list.map(converter).toList(),
    total: source.total,
    page: source.page,
    limit: source.limit,
    hasMore: source.hasMore,
  );
}
