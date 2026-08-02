import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/env.dart';
import '../../core/errors/error_interceptor.dart';
import '../../core/network/auth_interceptor.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/session_event_bus.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/storage/shared_prefs_storage.dart';

/// 安全存储（token / 用户资料 JSON）。
final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorage(const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  ));
});

/// SharedPreferences 异步初始化。
final sharedPreferencesProvider = FutureProvider<SharedPreferences>(
  (ref) async => SharedPreferences.getInstance(),
);

/// 偏好存储（同步包装，依赖 [sharedPreferencesProvider]）。
final sharedPrefsStorageProvider = Provider<SharedPrefsStorage?>((ref) {
  final async = ref.watch(sharedPreferencesProvider);
  return async.maybeWhen(
    data: (prefs) => SharedPrefsStorage(prefs),
    orElse: () => null,
  );
});

/// 当前应用语言代码（'zh' / 'en'）。
///
/// 读取 [SharedPrefsStorage] 持久化的语言偏好；通过 [LocaleController.setLocale]
/// 修改时会同步写入存储并触发 [MaterialApp] 重建，使切换即时生效。
class LocaleController extends Notifier<String> {
  @override
  String build() {
    ref.watch(sharedPreferencesProvider);
    return ref.read(sharedPrefsStorageProvider)?.getLocale() ?? 'zh';
  }

  Future<void> setLocale(String code) async {
    await ref.read(sharedPrefsStorageProvider)?.setLocale(code);
    state = code;
  }
}

final localeProvider =
    NotifierProvider<LocaleController, String>(LocaleController.new);

/// 会话事件总线：401 失效事件解耦传递。
final sessionEventBusProvider = Provider<SessionEventBus>(
  (ref) => SessionEventBus(),
);

/// Dio 实例（含 AuthInterceptor / ErrorInterceptor / LogInterceptor）。
final dioProvider = Provider<Dio>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  final bus = ref.watch(sessionEventBusProvider);
  final dio = Dio(BaseOptions(
    baseUrl: Env.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
    headers: const {'Content-Type': 'application/json'},
  ));
  dio.interceptors.addAll([
    AuthInterceptor(
      secureStorage: secureStorage,
      onSessionExpired: () async {
        bus.emit(SessionEvent.expired);
      },
    ),
    const ErrorInterceptor(),
    LogInterceptor(
      requestBody: Env.isDev,
      responseBody: Env.isDev,
      requestHeader: false,
      responseHeader: false,
    ),
  ]);
  ref.onDispose(dio.close);
  return dio;
});

/// 网络客户端封装（业务 Repository 统一使用）。
final dioClientProvider = Provider<DioClient>(
  (ref) => DioClient(ref.watch(dioProvider)),
);
