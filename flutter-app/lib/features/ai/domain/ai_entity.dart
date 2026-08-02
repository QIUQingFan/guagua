enum AiRole { user, assistant }

enum AiActionType { addToCart, buyNow, viewProduct, unknown }

enum AiMessageStatus { streaming, done, failed }

class AiActionEntity {
  const AiActionEntity({
    required this.type,
    this.productId,
    this.name,
    this.price,
    this.cover,
  });

  final AiActionType type;
  final int? productId;
  final String? name;
  final double? price;
  final String? cover;

  factory AiActionEntity.fromJson(Map<String, dynamic> json) {
    final raw = (json['type'] ?? '').toString();
    final type = switch (raw) {
      'add_to_cart' => AiActionType.addToCart,
      'buy_now' => AiActionType.buyNow,
      'view_product' => AiActionType.viewProduct,
      _ => AiActionType.unknown,
    };
    return AiActionEntity(
      type: type,
      productId:
          (json['productId'] as num?)?.toInt() ??
          (json['product_id'] as num?)?.toInt(),
      name: (json['name'] ?? json['title'])?.toString(),
      price: (json['price'] as num?)?.toDouble(),
      cover: (json['cover'] ?? json['image'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': switch (type) {
      AiActionType.addToCart => 'add_to_cart',
      AiActionType.buyNow => 'buy_now',
      AiActionType.viewProduct => 'view_product',
      AiActionType.unknown => 'unknown',
    },
    if (productId != null) 'productId': productId,
    if (name != null) 'name': name,
    if (price != null) 'price': price,
    if (cover != null) 'cover': cover,
  };

  bool get isValid =>
      type != AiActionType.unknown && productId != null && productId! > 0;
}

class AiMessageEntity {
  const AiMessageEntity({
    required this.id,
    required this.role,
    required this.content,
    this.actions = const [],
    this.status = AiMessageStatus.done,
    this.createdAt,
  });

  final int id;
  final AiRole role;
  final String content;
  final List<AiActionEntity> actions;
  final AiMessageStatus status;
  final DateTime? createdAt;

  bool get isUser => role == AiRole.user;
  bool get isStreaming => status == AiMessageStatus.streaming;
  bool get isFailed => status == AiMessageStatus.failed;

  AiMessageEntity copyWith({
    int? id,
    AiRole? role,
    String? content,
    List<AiActionEntity>? actions,
    AiMessageStatus? status,
    DateTime? createdAt,
  }) {
    return AiMessageEntity(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      actions: actions ?? this.actions,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role == AiRole.user ? 'user' : 'assistant',
    'content': content,
    if (actions.isNotEmpty) 'actions': actions.map((a) => a.toJson()).toList(),
    'status': switch (status) {
      AiMessageStatus.streaming => 'streaming',
      AiMessageStatus.done => 'done',
      AiMessageStatus.failed => 'failed',
    },
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  };

  factory AiMessageEntity.fromJson(Map<String, dynamic> json) {
    final rawRole = (json['role'] ?? 'user').toString();
    final rawStatus = (json['status'] ?? 'done').toString();
    return AiMessageEntity(
      id: (json['id'] as num?)?.toInt() ?? 0,
      role: rawRole == 'assistant' ? AiRole.assistant : AiRole.user,
      content: (json['content'] ?? '').toString(),
      actions:
          (json['actions'] as List<dynamic>?)
              ?.map((a) => AiActionEntity.fromJson(a as Map<String, dynamic>))
              .toList() ??
          const [],
      status: switch (rawStatus) {
        'streaming' => AiMessageStatus.streaming,
        'failed' => AiMessageStatus.failed,
        _ => AiMessageStatus.done,
      },
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }
}

/// SSE 流式响应 chunk
class AiChunk {
  const AiChunk({
    this.delta,
    this.action,
    this.conversationId,
    this.done = false,
  });

  final String? delta;
  final AiActionEntity? action;
  final int? conversationId;
  final bool done;

  factory AiChunk.fromJson(Map<String, dynamic> json) {
    final doneRaw = json['done'];
    final done = doneRaw is bool
        ? doneRaw
        : (doneRaw is num
              ? doneRaw.toInt() == 1
              : doneRaw.toString().toLowerCase() == 'true');
    final token = (json['token'] as String?)?.trim();
    final delta = (json['delta'] as String?)?.trim();
    return AiChunk(
      delta: token?.isNotEmpty == true ? token : delta,
      action: json['action'] is Map<String, dynamic>
          ? AiActionEntity.fromJson(json['action'] as Map<String, dynamic>)
          : null,
      conversationId: (json['conversation_id'] as num?)?.toInt(),
      done: done,
    );
  }
}
