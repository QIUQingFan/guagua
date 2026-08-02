import 'dart:convert';

import '../../../core/utils/formatters.dart';
import '../domain/shop_entities.dart';

class ProductCategoryDto {
  const ProductCategoryDto({
    required this.id,
    required this.name,
    this.icon = '',
    this.parentId,
  });

  final int id;
  final String name;
  final String icon;
  final int? parentId;

  factory ProductCategoryDto.fromJson(Map<String, dynamic> json) {
    return ProductCategoryDto(
      id: parseInt(json['id']),
      name: cleanString(json['name']),
      icon: cleanString(json['icon']),
      parentId: tryParseNum(json['parent_id'])?.toInt(),
    );
  }

  ProductCategoryEntity toEntity() =>
      ProductCategoryEntity(id: id, name: name, icon: icon, parentId: parentId);
}

class ProductSpecDto {
  const ProductSpecDto({
    required this.id,
    required this.name,
    required this.values,
  });

  final int id;
  final String name;
  final List<String> values;

  factory ProductSpecDto.fromJson(Map<String, dynamic> json) {
    final valuesRaw = json['values'];
    return ProductSpecDto(
      id: parseInt(json['id']),
      name: cleanString(json['name']),
      values: valuesRaw is List
          ? valuesRaw.map((e) => cleanString(e)).toList()
          : const [],
    );
  }

  ProductSpecEntity toEntity() =>
      ProductSpecEntity(id: id, name: name, values: values);
}

class ProductDto {
  const ProductDto({
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
  final List<ProductSpecDto> specs;
  final int sellerId;
  final String sellerName;
  final List<String> tags;
  final DateTime? createdAt;

  factory ProductDto.fromJson(Map<String, dynamic> json) {
    final imagesRaw = json['images'];
    final specsRaw = json['specs'];
    final tagsRaw = json['tags'];

    List<String> images = [];
    if (imagesRaw is List) {
      images = imagesRaw
          .map((e) => cleanString(e))
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (imagesRaw is String && imagesRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(imagesRaw);
        if (decoded is List) {
          images = decoded
              .map((e) => cleanString(e))
              .where((s) => s.isNotEmpty)
              .toList();
        } else {
          images = [cleanString(imagesRaw)];
        }
      } catch (_) {
        images = [cleanString(imagesRaw)];
      }
    }

    final singleCover = cleanString(
      json['cover'] ??
          json['cover_image'] ??
          json['cover_url'] ??
          json['image'] ??
          json['image_url'] ??
          json['main_image'] ??
          json['pic'] ??
          json['picture'],
    );
    if (images.isEmpty && singleCover.isNotEmpty) {
      images = [singleCover];
    }

    return ProductDto(
      id: parseInt(json['id']),
      title: cleanString(json['title'] ?? json['name']),
      price: parseDouble(json['price']),
      originalPrice: tryParseNum(json['original_price'])?.toDouble(),
      images: images,
      cover: singleCover,
      description: cleanString(json['description']),
      salesCount: parseInt(
        json['sales_count'] ?? json['sales'] ?? json['sold'],
      ),
      stock: parseInt(json['stock']),
      categoryId: tryParseNum(json['category_id'])?.toInt(),
      specs: specsRaw is List
          ? specsRaw
                .map((e) => ProductSpecDto.fromJson(e as Map<String, dynamic>))
                .toList()
          : const [],
      sellerId: parseInt(json['seller_id']),
      sellerName: cleanString(json['seller_name']),
      tags: tagsRaw is List
          ? tagsRaw.map((e) => cleanString(e)).toList()
          : const [],
      createdAt: tryParseDateTime(json['created_at'] as String?),
    );
  }

  ProductEntity toEntity() {
    final fullImages = images.map(getFullImageUrl).toList();
    final fullCover = getFullImageUrl(cover);
    return ProductEntity(
      id: id,
      title: title,
      price: price,
      originalPrice: originalPrice,
      images: fullImages,
      cover: fullCover.isEmpty && fullImages.isNotEmpty
          ? fullImages.first
          : fullCover,
      description: description,
      salesCount: salesCount,
      stock: stock,
      categoryId: categoryId,
      specs: specs.map((e) => e.toEntity()).toList(),
      sellerId: sellerId,
      sellerName: sellerName,
      tags: tags,
      createdAt: createdAt,
    );
  }
}

class CartItemDto {
  const CartItemDto({
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

  factory CartItemDto.fromJson(Map<String, dynamic> json) {
    final product = json['product'] is Map<String, dynamic>
        ? json['product'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return CartItemDto(
      id: parseInt(json['id']),
      productId: parseInt(
        json['product_id'] ?? json['productId'] ?? product['id'],
      ),
      title: cleanString(
        json['title'] ?? json['name'] ?? product['title'] ?? product['name'],
      ),
      price: parseDouble(json['price'] ?? product['price']),
      quantity: parseInt(json['quantity'], fallback: 1),
      selected: (json['selected'] as bool?) ?? false,
      cover: cleanString(
        json['cover'] ??
            json['cover_image'] ??
            json['cover_url'] ??
            json['image'] ??
            product['cover'] ??
            product['cover_image'] ??
            product['cover_url'] ??
            product['image'] ??
            product['image_url'] ??
            product['main_image'],
      ),
      spec: cleanString(json['spec'] ?? json['sku_spec'] ?? product['spec']),
      stock: parseInt(json['stock'] ?? product['stock']),
    );
  }

  CartItemEntity toEntity() => CartItemEntity(
    id: id,
    productId: productId,
    title: title,
    price: price,
    quantity: quantity,
    selected: selected,
    cover: getFullImageUrl(cover),
    spec: spec,
    stock: stock,
  );
}

class OrderItemDto {
  const OrderItemDto({
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

  factory OrderItemDto.fromJson(Map<String, dynamic> json) {
    return OrderItemDto(
      productId: parseInt(json['product_id']),
      title: cleanString(json['title'] ?? json['name']),
      price: parseDouble(json['price']),
      quantity: parseInt(json['quantity'], fallback: 1),
      cover: cleanString(
        json['cover'] ?? json['cover_image'] ?? json['cover_url'],
      ),
      spec: cleanString(json['spec']),
    );
  }

  OrderItemEntity toEntity() => OrderItemEntity(
    productId: productId,
    title: title,
    price: price,
    quantity: quantity,
    cover: getFullImageUrl(cover),
    spec: spec,
  );
}

class OrderStatusLogDto {
  const OrderStatusLogDto({
    required this.status,
    required this.time,
    this.remark = '',
  });

  final String status;
  final DateTime time;
  final String remark;

  factory OrderStatusLogDto.fromJson(Map<String, dynamic> json) {
    return OrderStatusLogDto(
      status: cleanString(json['status']),
      time:
          tryParseDateTime((json['time'] ?? json['created_at']) as String?) ??
          DateTime.now(),
      remark: cleanString(json['remark']),
    );
  }

  OrderStatusLog toEntity() => OrderStatusLog(
    status: OrderStatus.fromValue(status),
    time: time,
    remark: remark,
  );
}

class OrderDto {
  const OrderDto({
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
  final String status;
  final List<OrderItemDto> items;
  final double totalAmount;
  final DateTime createdAt;
  final String addressName;
  final String addressPhone;
  final String addressDetail;
  final String? remark;
  final DateTime? updatedAt;
  final List<OrderStatusLogDto> statusLogs;

  factory OrderDto.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    final logsRaw = json['status_logs'] ?? json['logs'];
    return OrderDto(
      id: parseInt(json['id']),
      orderNo: cleanString(json['order_no'] ?? json['orderNo']),
      status: cleanString(json['status']),
      items: itemsRaw is List
          ? itemsRaw
                .map((e) => OrderItemDto.fromJson(e as Map<String, dynamic>))
                .toList()
          : const [],
      totalAmount: parseDouble(json['total_amount'] ?? json['amount']),
      createdAt:
          tryParseDateTime(json['created_at'] as String?) ?? DateTime.now(),
      addressName: cleanString(json['address_name'] ?? json['receiver_name']),
      addressPhone: cleanString(
        json['address_phone'] ?? json['receiver_phone'],
      ),
      addressDetail: cleanString(json['address_detail'] ?? json['address']),
      remark: json['remark'] as String?,
      updatedAt: tryParseDateTime(json['updated_at'] as String?),
      statusLogs: logsRaw is List
          ? logsRaw
                .map(
                  (e) => OrderStatusLogDto.fromJson(e as Map<String, dynamic>),
                )
                .toList()
          : const [],
    );
  }

  OrderEntity toEntity() => OrderEntity(
    id: id,
    orderNo: orderNo,
    status: OrderStatus.fromValue(status),
    items: items.map((e) => e.toEntity()).toList(),
    totalAmount: totalAmount,
    createdAt: createdAt,
    addressName: addressName,
    addressPhone: addressPhone,
    addressDetail: addressDetail,
    remark: remark,
    updatedAt: updatedAt,
    statusLogs: statusLogs.map((e) => e.toEntity()).toList(),
  );
}

class AddressDto {
  const AddressDto({
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

  factory AddressDto.fromJson(Map<String, dynamic> json) {
    return AddressDto(
      id: parseInt(json['id']),
      name: cleanString(json['name'] ?? json['receiver_name']),
      phone: cleanString(json['phone'] ?? json['receiver_phone']),
      detail: cleanString(json['detail'] ?? json['address']),
      isDefault:
          (json['is_default'] as bool?) ??
          (json['isDefault'] as bool?) ??
          false,
    );
  }

  AddressEntity toEntity() => AddressEntity(
    id: id,
    name: name,
    phone: phone,
    detail: detail,
    isDefault: isDefault,
  );
}

class AddToCartRequest {
  const AddToCartRequest({
    required this.productId,
    required this.quantity,
    this.spec,
  });

  final int productId;
  final int quantity;
  final String? spec;

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'quantity': quantity,
    if (spec != null) 'spec': spec,
  };
}

class CreateOrderRequest {
  const CreateOrderRequest({
    required this.items,
    required this.addressId,
    this.remark,
  });

  final List<CreateOrderItem> items;
  final int addressId;
  final String? remark;

  Map<String, dynamic> toJson() => {
    'items': items.map((e) => e.toJson()).toList(),
    'address_id': addressId,
    if (remark != null) 'remark': remark,
  };
}

class CreateOrderItem {
  const CreateOrderItem({
    required this.productId,
    required this.quantity,
    this.spec,
    this.title,
    this.cover,
    this.price,
  });

  final int productId;
  final int quantity;
  final String? spec;
  final String? title;
  final String? cover;
  final double? price;

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'quantity': quantity,
    if (spec != null) 'spec': spec,
  };
}

class SaveAddressRequest {
  const SaveAddressRequest({
    this.id,
    required this.name,
    required this.phone,
    required this.detail,
    this.isDefault = false,
  });

  final int? id;
  final String name;
  final String phone;
  final String detail;
  final bool isDefault;

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'phone': phone,
    'detail': detail,
    'is_default': isDefault,
  };
}
