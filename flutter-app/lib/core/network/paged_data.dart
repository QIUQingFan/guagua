/// 后端分页响应适配
class PagedData<T> {
  const PagedData({
    required this.list,
    required this.total,
    required this.page,
    required this.limit,
    required this.hasMore,
  });

  final List<T> list;
  final int total;
  final int page;
  final int limit;
  final bool hasMore;

  bool get isEmpty => list.isEmpty;
  int get pages => limit <= 0 ? 0 : (total / limit).ceil();

  /// 从后端 `pagination` 对象与已解码列表构造
  factory PagedData.fromBackend({
    required List<T> list,
    required Map<String, dynamic>? pagination,
  }) {
    final page = (pagination?['page'] as num?)?.toInt() ?? 1;
    final limit = (pagination?['limit'] as num?)?.toInt() ?? list.length;
    final total = (pagination?['total'] as num?)?.toInt() ?? list.length;
    final pages =
        (pagination?['pages'] as num?)?.toInt() ??
        (pagination?['totalPages'] as num?)?.toInt() ??
        (limit > 0 ? (total / limit).ceil() : 1);
    return PagedData<T>(
      list: list,
      total: total,
      page: page,
      limit: limit,
      hasMore: page < pages,
    );
  }

  PagedData<T> copyWith({
    List<T>? list,
    int? total,
    int? page,
    int? limit,
    bool? hasMore,
  }) {
    return PagedData<T>(
      list: list ?? this.list,
      total: total ?? this.total,
      page: page ?? this.page,
      limit: limit ?? this.limit,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}
