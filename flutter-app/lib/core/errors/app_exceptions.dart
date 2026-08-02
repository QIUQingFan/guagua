/// 统一异常定义。
///
/// 业务错误抛 [ApiException]，网络错误抛 [NetworkException]，
/// 鉴权失败抛 [UnauthorizedException] 由拦截器处理刷新或登出。
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.data});

  final int code;
  final String message;
  final dynamic data;

  bool get isUnauthorized => code == 401;
  bool get isForbidden => code == 403;
  bool get isNotFound => code == 404;

  @override
  String toString() => 'ApiException($code): $message';
}

/// 网络层错误（连接超时、断网、DNS 失败等）。
class NetworkException extends ApiException {
  const NetworkException([String? message])
      : super(-1, message ?? '网络连接失败，请检查网络');
}

/// 401 鉴权失败，触发刷新或强制登出。
class UnauthorizedException extends ApiException {
  const UnauthorizedException([String? message])
      : super(401, message ?? '登录已过期，请重新登录');
}

/// 业务字段校验错误。
class ValidationException extends ApiException {
  const ValidationException(String message) : super(400, message);
}
