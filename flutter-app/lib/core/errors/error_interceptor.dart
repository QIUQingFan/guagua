import 'package:dio/dio.dart';

import '../errors/app_exceptions.dart';

/// 错误拦截器：将 [DioException] 归一化为业务异常。
///
/// - 连接超时 / 断网 → [NetworkException]
/// - 401 → [UnauthorizedException]（由 AuthInterceptor 优先处理）
/// - 其他 HTTP 错误 → [ApiException]
class ErrorInterceptor extends Interceptor {
  const ErrorInterceptor();

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final dioErr = _convert(err);
    handler.next(dioErr);
  }

  DioException _convert(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return DioException(
          requestOptions: err.requestOptions,
          type: err.type,
          error: const NetworkException(),
          message: '网络连接失败，请检查网络',
          response: err.response,
        );
      case DioExceptionType.badResponse:
        final status = err.response?.statusCode ?? 0;
        String message;
        if (err.response?.data is Map<String, dynamic>) {
          message = (err.response!.data as Map<String, dynamic>)['message']
                  as String? ??
              err.message ??
              '请求失败';
        } else {
          message = err.message ?? '请求失败';
        }
        ApiException ex;
        if (status == 401) {
          ex = UnauthorizedException(message);
        } else {
          ex = ApiException(status, message);
        }
        return DioException(
          requestOptions: err.requestOptions,
          type: err.type,
          error: ex,
          response: err.response,
          message: message,
        );
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
      case DioExceptionType.transformTimeout:
        if (err.error is ApiException) return err;
        return DioException(
          requestOptions: err.requestOptions,
          type: err.type,
          error: const NetworkException(),
          message: err.message ?? '网络异常',
        );
    }
  }
}
