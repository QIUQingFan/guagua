import '../../core/errors/app_exceptions.dart';

/// 后端统一响应封包：`{code, message, data}`。
///
/// `code === 200` 为成功；其他视为业务错误，由 Repository 解包时抛 [ApiException]。
class ApiResponse<T> {
  const ApiResponse({
    required this.code,
    required this.message,
    this.data,
  });

  final int code;
  final String message;
  final T? data;

  bool get isSuccess => code == 200;

  /// 从 JSON 解析。
  ///
  /// [decode] 将 `data` 字段转为具体类型；当 `data` 为 null 时返回 null。
  static ApiResponse<T?> fromJson<T>(
    Map<String, dynamic> json, {
    T Function(dynamic)? decode,
  }) {
    return ApiResponse<T?>(
      code: (json['code'] as num?)?.toInt() ?? -1,
      message: (json['message'] as String?) ?? '',
      data: json['data'] == null ? null : decode?.call(json['data']),
    );
  }

  /// 解包并校验：失败抛 [ApiException]，成功返回 data。
  ///
  /// 若调用方期望 data 必非空，可使用 [unwrap].
  T unwrap() {
    if (!isSuccess) throw ApiException(code, message);
    final d = data;
    if (d == null) throw const ApiException(500, '响应数据为空');
    return d as T;
  }

  /// 解包但不校验空值（用于无 data 的成功响应）。
  void ensureSuccess() {
    if (!isSuccess) throw ApiException(code, message);
  }
}
