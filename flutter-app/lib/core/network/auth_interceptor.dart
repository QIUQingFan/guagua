import 'dart:async';

import 'package:dio/dio.dart';

import '../constants/api_paths.dart';
import '../constants/env.dart';
import '../constants/storage_keys.dart';
import '../errors/app_exceptions.dart';
import '../storage/secure_storage.dart';
import 'api_response.dart';

/// 鉴权拦截
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.secureStorage,
    required this.onSessionExpired,
  });

  final SecureStorage secureStorage;
  final Future<void> Function() onSessionExpired;

  bool _refreshing = false;
  Completer<bool>? _refreshCompleter;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.path == ApiPaths.authRefresh) {
      handler.next(options);
      return;
    }
    final token = await secureStorage.read(StorageKeys.accessToken);
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final status = err.response?.statusCode;
    final isRefreshCall = err.requestOptions.path == ApiPaths.authRefresh;
    if (status != 401 || isRefreshCall) {
      handler.next(err);
      return;
    }

    final refreshed = await _refreshToken();
    if (!refreshed) {
      await onSessionExpired();
      handler.next(
        DioException(
          requestOptions: err.requestOptions,
          type: err.type,
          error: const UnauthorizedException(),
          response: err.response,
          message: '登录已过期',
        ),
      );
      return;
    }

    // 刷新成功，重放原请求
    try {
      final newToken = await secureStorage.read(StorageKeys.accessToken);
      final clone = err.requestOptions
        ..headers['Authorization'] = 'Bearer $newToken';
      final dio = Dio(BaseOptions(baseUrl: Env.apiBaseUrl));
      final res = await dio.fetch<dynamic>(clone);
      handler.resolve(res);
    } on DioException catch (e) {
      handler.next(e);
    } catch (e) {
      handler.next(
        DioException(
          requestOptions: err.requestOptions,
          error: e,
          message: '重放请求失败',
        ),
      );
    }
  }

  Future<bool> _refreshToken() async {
    // 互斥：已有刷新在进行，等待结果
    if (_refreshing) {
      return _refreshCompleter?.future ?? Future.value(false);
    }
    _refreshing = true;
    _refreshCompleter = Completer<bool>();

    try {
      final refresh = await secureStorage.read(StorageKeys.refreshToken);
      if (refresh == null || refresh.isEmpty) {
        _refreshCompleter!.complete(false);
        return false;
      }

      final bareDio = Dio(BaseOptions(baseUrl: Env.apiBaseUrl));
      final res = await bareDio.post<dynamic>(
        ApiPaths.authRefresh,
        data: {'refresh_token': refresh},
      );

      final api = ApiResponse.fromJson(
        res.data as Map<String, dynamic>,
        decode: (d) => d as Map<String, dynamic>,
      );
      if (!api.isSuccess || api.data == null) {
        _refreshCompleter!.complete(false);
        return false;
      }

      final data = api.data!;
      final newAccess = data['access_token'] as String?;
      final newRefresh = data['refresh_token'] as String?;
      if (newAccess == null) {
        _refreshCompleter!.complete(false);
        return false;
      }

      await secureStorage.write(StorageKeys.accessToken, newAccess);
      if (newRefresh != null) {
        await secureStorage.write(StorageKeys.refreshToken, newRefresh);
      }

      _refreshCompleter!.complete(true);
      return true;
    } on DioException {
      _refreshCompleter!.complete(false);
      return false;
    } catch (e) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshing = false;
      _refreshCompleter = null;
    }
  }
}
