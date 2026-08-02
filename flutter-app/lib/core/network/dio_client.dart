import 'package:dio/dio.dart';

import '../errors/app_exceptions.dart';
import 'api_response.dart';
import 'paged_data.dart';

/// 网络客户端封装：统一解包 [ApiResponse]、归一化分页、异常映射。
class DioClient {
  const DioClient(this._dio);

  final Dio _dio;

  /// GET 请求并解包为单对象。
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(dynamic) decode,
  }) => _request<T>(() => _dio.get(path, queryParameters: query), decode);

  /// GET 请求并解包为分页列表。
  Future<PagedData<T>> getPaged<T>(
    String path, {
    Map<String, dynamic>? query,
    required String listKey,
    required T Function(Map<String, dynamic>) decode,
  }) async {
    final raw = await _request<Map<String, dynamic>>(
      () => _dio.get(path, queryParameters: query),
      (d) => d as Map<String, dynamic>,
    );
    final listRaw = raw[listKey] ?? raw['data'] ?? raw['list'] ?? raw['items'];
    final list = (listRaw is List<dynamic> ? listRaw : const <dynamic>[])
        .map((e) => decode(e as Map<String, dynamic>))
        .toList();
    final pagination = raw['pagination'] is Map<String, dynamic>
        ? raw['pagination'] as Map<String, dynamic>
        : raw;
    return PagedData<T>.fromBackend(list: list, pagination: pagination);
  }

  /// POST 请求并解包。
  Future<T> post<T>(
    String path, {
    dynamic data,
    required T Function(dynamic) decode,
  }) => _request<T>(() => _dio.post(path, data: data), decode);

  /// PUT 请求并解包。
  Future<T> put<T>(
    String path, {
    dynamic data,
    required T Function(dynamic) decode,
  }) => _request<T>(() => _dio.put(path, data: data), decode);

  Future<T> delete<T>(
    String path, {
    dynamic data,
    required T Function(dynamic) decode,
  }) => _request<T>(() => _dio.delete(path, data: data), decode);

  Future<void> postVoid(String path, {dynamic data}) async {
    await _request<Map<String, dynamic>?>(
      () => _dio.post(path, data: data),
      (d) => d as Map<String, dynamic>?,
    );
  }

  Future<void> putVoid(String path, {dynamic data}) async {
    await _request<Map<String, dynamic>?>(
      () => _dio.put(path, data: data),
      (d) => d as Map<String, dynamic>?,
    );
  }

  Future<void> deleteVoid(String path, {dynamic data}) async {
    await _request<Map<String, dynamic>?>(
      () => _dio.delete(path, data: data),
      (d) => d as Map<String, dynamic>?,
    );
  }

  /// 文件上传
  Future<T> upload<T>(
    String path, {
    required FormData form,
    required T Function(dynamic) decode,
    void Function(int sent, int total)? onProgress,
  }) async {
    final res = await _dio.post<dynamic>(
      path,
      data: form,
      onSendProgress: onProgress,
      options: Options(contentType: 'multipart/form-data'),
    );
    final api = ApiResponse.fromJson(
      res.data as Map<String, dynamic>,
      decode: decode,
    );
    if (!api.isSuccess) throw ApiException(api.code, api.message);
    return decode(res.data['data']);
  }

  Dio get raw => _dio;

  Future<T> _request<T>(
    Future<Response> Function() request,
    T Function(dynamic) decode,
  ) async {
    try {
      final res = await request();
      final api = ApiResponse.fromJson(
        res.data is Map<String, dynamic>
            ? res.data as Map<String, dynamic>
            : <String, dynamic>{'code': 200, 'message': '', 'data': res.data},
        decode: decode,
      );
      if (!api.isSuccess) throw ApiException(api.code, api.message);
      final d = api.data;
      if (d == null) {
        // 允许空 data：返回 null 转换为 T（调用方需保证 T 可空或使用 postVoid）
        return null as T;
      }
      return d;
    } on DioException catch (e) {
      // ErrorInterceptor 已将错误归一化为 ApiException 装在 error 字段
      if (e.error is ApiException) throw e.error as ApiException;
      throw const NetworkException();
    }
  }
}
