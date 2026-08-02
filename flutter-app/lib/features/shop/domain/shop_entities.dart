import '../../../core/utils/formatters.dart';

/// 商品分类。
class ProductCategoryEntity {
  const ProductCategoryEntity({
    required this.id,
    required this.name,
    this.icon = '',
    this.parentId,
  });

  final int id;
  final String name;
  final String icon;
  final int? parentId;
}

/// 商品规格选项。
class ProductSpecEntity {
  const ProductSpecEntity({
    required this.id,
    required this.name,
    required this.values,
  });

  final int id;
  final String name; 
  final List<String> values; 
}

/// 商品实体。
class ProductEntity {
  const ProductEntity({
    required this.id,
    required this.title,
    required this.price,
    this.originalPrice,
    this.images = const [],
    this.cover = '',
    this.description = '',
    this.salesCount = 0,
    this.stock = 0,
    this.categoryId,
    this.specs = const [],
    this.sellerId = 0,
    this.sellerName = '',
    this.tags = const [],
    this.createdAt,
  });

  final int id;
  final String title;
  final double price;
  final double? originalPrice; 
  final List<String> images;
  final String cover;
  final String description;
  final int salesCount;
  final int stock;
  final int? categoryId;
  final List<ProductSpecEntity> specs;
  final int sellerId; 
  final String sellerName;
  final List<String> tags;
  final DateTime? createdAt;

  bool get hasDiscount =>
      originalPrice != null && originalPrice! > price;
}

/// 购物车项。
class CartItemEntity {
  const CartItemEntity({
    required this.id,
    required this.productId,
    required this.title,
    required this.price,
    required this.quantity,
    required this.selected,
    this.cover = '',
    this.spec = '',
    this.stock = 0,
  });

  final int id; 
  final int productId;
  final String title;
  final double price;
  final int quantity;
  final bool selected;
  final String cover;
  final String spec; 
  final int stock;

  double get subtotal => price * quantity;

  CartItemEntity copyWith({
    int? id,
    int? productId,
    String? title,
    double? price,
    int? quantity,
    bool? selected,
    String? cover,
    String? spec,
    int? stock,
  }) {
    return CartItemEntity(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      title: title ?? this.title,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      selected: selected ?? this.selected,
      cover: cover ?? this.cover,
      spec: spec ?? this.spec,
      stock: stock ?? this.stock,
    );
  }
}

/// 购物车聚合。
class CartEntity {
  const CartEntity({this.items = const []});

  final List<CartItemEntity> items;

  List<CartItemEntity> get selectedItems =>
      items.where((i) => i.selected).toList();

  int get selectedCount =>
      selectedItems.fold<int>(0, (s, i) => s + i.quantity);

  double get selectedTotalPrice =>
      selectedItems.fold<double>(0, (s, i) => s + i.subtotal);

  bool get allSelected => items.isNotEmpty && items.every((i) => i.selected);

  CartEntity toggleItem(int itemId, bool selected) {
    return CartEntity(
      items: items
          .map((i) => i.id == itemId ? i.copyWith(selected: selected) : i)
          .toList(),
    );
  }

  CartEntity toggleAll(bool selected) {
    return CartEntity(
      items: items.map((i) => i.copyWith(selected: selected)).toList(),
    );
  }

  CartEntity updateQuantity(int itemId, int quantity) {
    return CartEntity(
      items: items
          .map((i) => i.id == itemId ? i.copyWith(quantity: quantity) : i)
          .toList(),
    );
  }

  CartEntity removeItem(int itemId) {
    return CartEntity(
      items: items.where((i) => i.id != itemId).toList(),
    );
  }
}

/// 订单状态枚举。
enum OrderStatus {
  pendingPay('pending_pay'),
  pendingShip('pending_ship'),
  pendingReceive('pending_receive'),
  completed('completed'),
  cancelled('cancelled');

  const OrderStatus(this.value);
  final String value;

  static OrderStatus fromValue(String? v) {
    return OrderStatus.values.firstWhere(
      (e) => e.value == v,
      orElse: () => OrderStatus.pendingPay,
    );
  }

  /// 显示用本地化 key（由 UI 层翻译）。
  String get l10nKey => switch (this) {
        OrderStatus.pendingPay => 'shopOrderPendingPay',
        OrderStatus.pendingShip => 'shopOrderPendingShip',
        OrderStatus.pendingReceive => 'shopOrderPendingReceive',
        OrderStatus.completed => 'shopOrderCompleted',
        OrderStatus.cancelled => 'shopOrderCancelled',
      };
}

/// 订单商品项。
class OrderItemEntity {
  const OrderItemEntity({
    required this.productId,
    required this.title,
    required this.price,
    required this.quantity,
    this.cover = '',
    this.spec = '',
  });

  final int productId;
  final String title;
  final double price;
  final int quantity;
  final String cover;
  final String spec;

  double get subtotal => price * quantity;
}

/// 订单实体。
class OrderEntity {
  const OrderEntity({
    required this.id,
    required this.orderNo,
    required this.status,
    required this.items,
    required this.totalAmount,
    required this.createdAt,
    this.addressName = '',
    this.addressPhone = '',
    this.addressDetail = '',
    this.remark,
    this.updatedAt,
    this.statusLogs = const [],
  });

  final int id;
  final String orderNo;
  final OrderStatus status;
  final List<OrderItemEntity> items;
  final double totalAmount;
  final DateTime createdAt;
  final String addressName;
  final String addressPhone;
  final String addressDetail;
  final String? remark;
  final DateTime? updatedAt;
  final List<OrderStatusLog> statusLogs;

  int get itemCount => items.fold<int>(0, (s, i) => s + i.quantity);
}

/// 订单状态日志（时间轴）。
class OrderStatusLog {
  const OrderStatusLog({
    required this.status,
    required this.time,
    this.remark = '',
  });

  final OrderStatus status;
  final DateTime time;
  final String remark;

  String get displayTime => Formatters.dateTime(time);
}

/// 收货地址实体。
class AddressEntity {
  const AddressEntity({
    required this.id,
    required this.name,
    required this.phone,
    required this.detail,
    this.isDefault = false,
  });

  final int id;
  final String name;
  final String phone;
  final String detail;
  final bool isDefault;

  AddressEntity copyWith({
    int? id,
    String? name,
    String? phone,
    String? detail,
    bool? isDefault,
  }) {
    return AddressEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      detail: detail ?? this.detail,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
