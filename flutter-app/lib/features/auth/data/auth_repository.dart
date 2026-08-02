import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/storage_keys.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../shared/domain/user_entity.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/auth_entity.dart';
import 'auth_api.dart';

/// 认证
class AuthRepository {
  AuthRepository({required AuthApi api, required SecureStorage secureStorage})
    : _api = api,
      _storage = secureStorage;

  final AuthApi _api;
  final SecureStorage _storage;

  Future<AuthEntity> login(String userId, String password) async {
    final dto = await _api.login(userId: userId, password: password);
    final entity = dto.toEntity();
    await _persist(entity);
    return entity;
  }

  Future<AuthEntity> register({
    required String userId,
    required String nickname,
    required String password,
    required String captchaId,
    required String captchaText,
    String? avatar,
    String? bio,
    String? location,
  }) async {
    final dto = await _api.register(
      userId: userId,
      nickname: nickname,
      password: password,
      captchaId: captchaId,
      captchaText: captchaText,
      avatar: avatar,
      bio: bio,
      location: location,
    );
    final entity = dto.toEntity();
    await _persist(entity);
    return entity;
  }

  /// 退出
  Future<void> logout() async {
    try {
      await _api.logout();
    } finally {
      await clearLocal();
    }
  }

  Future<AuthEntity?> restoreSession() async {
    final token = await _storage.read(StorageKeys.accessToken);
    if (token == null || token.isEmpty) return null;

    try {
      final userDto = await _api.me();
      final refresh = await _storage.read(StorageKeys.refreshToken) ?? '';
      await _persistUser(userDto.toEntity());
      return AuthEntity(
        user: userDto.toEntity(),
        tokens: TokenEntity(accessToken: token, refreshToken: refresh),
      );
    } catch (_) {
      await clearLocal();
      return null;
    }
  }

  Future<void> clearLocal() async {
    await _storage.delete(StorageKeys.accessToken);
    await _storage.delete(StorageKeys.refreshToken);
    await _storage.delete(StorageKeys.userProfile);
  }

  Future<void> updateLocalUser(UserEntity user) => _persistUser(user);

  Future<void> _persist(AuthEntity entity) async {
    await _storage.write(StorageKeys.accessToken, entity.tokens.accessToken);
    await _storage.write(StorageKeys.refreshToken, entity.tokens.refreshToken);
    await _persistUser(entity.user);
  }

  Future<void> _persistUser(UserEntity user) async {
    await _storage.write(
      StorageKeys.userProfile,
      jsonEncode({
        'id': user.id,
        'user_id': user.userId,
        'nickname': user.nickname,
        'avatar': user.avatar,
        'bio': user.bio,
        'location': user.location,
        'gender': user.gender,
        'follow_count': user.followCount,
        'fans_count': user.fansCount,
        'like_count': user.likeCount,
        'post_count': user.postCount,
        'verified': user.verified,
        'is_active': user.isActive,
        if (user.createdAt != null)
          'created_at': user.createdAt!.toIso8601String(),
      }),
    );
  }
}

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(dioClientProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(authApiProvider),
    secureStorage: ref.watch(secureStorageProvider),
  );
});
