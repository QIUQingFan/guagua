import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guagua/core/constants/storage_keys.dart';
import 'package:guagua/core/errors/app_exceptions.dart';
import 'package:guagua/core/storage/secure_storage.dart';
import 'package:guagua/features/auth/data/auth_api.dart';
import 'package:guagua/features/auth/data/auth_dto.dart';
import 'package:guagua/features/auth/data/auth_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthApi extends Mock implements AuthApi {}

class _MockSecureStorage extends Mock implements SecureStorage {}

const _userJson = {
  'id': 42,
  'user_id': 'guagua_001',
  'nickname': '瓜呱',
  'avatar': 'https://cdn.example.com/a.png',
  'bio': '热爱生活',
  'location': '上海',
  'gender': 1,
  'follow_count': 10,
  'fans_count': 100,
  'like_count': 1000,
  'post_count': 5,
  'verified': 1,
  'is_active': 1,
  'created_at': '2026-01-01T00:00:00.000Z',
};

const _tokensJson = {
  'access_token': 'access-abc',
  'refresh_token': 'refresh-xyz',
  'expires_in': 7200,
};

final _authDto = AuthDto.fromJson({'user': _userJson, 'tokens': _tokensJson});

final _userDto = UserDto.fromJson(_userJson);

void main() {
  late _MockAuthApi api;
  late _MockSecureStorage storage;
  late AuthRepository repo;

  setUp(() {
    api = _MockAuthApi();
    storage = _MockSecureStorage();
    repo = AuthRepository(api: api, secureStorage: storage);

    registerFallbackValue('');
    when(() => storage.write(any(), any())).thenAnswer((_) async {});
    when(() => storage.delete(any())).thenAnswer((_) async {});
  });

  group('AuthRepository.login', () {
    test('成功：返回 AuthEntity 并持久化 token / user', () async {
      when(
        () => api.login(userId: 'guagua_001', password: '123456'),
      ).thenAnswer((_) async => _authDto);

      final entity = await repo.login('guagua_001', '123456');

      expect(entity.user.id, 42);
      expect(entity.user.nickname, '瓜呱');
      expect(entity.user.isVerified, isTrue);
      expect(entity.tokens.accessToken, 'access-abc');
      expect(entity.tokens.refreshToken, 'refresh-xyz');
      expect(entity.tokens.expiresIn, 7200);

      final captured = verify(
        () => storage.write(captureAny(), captureAny()),
      ).captured;
      expect(captured.length, 6);
      expect(captured[0], StorageKeys.accessToken);
      expect(captured[1], 'access-abc');
      expect(captured[2], StorageKeys.refreshToken);
      expect(captured[3], 'refresh-xyz');
      expect(captured[4], StorageKeys.userProfile);
      final userJsonStr = captured[5] as String;
      final decoded = jsonDecode(userJsonStr) as Map<String, dynamic>;
      expect(decoded['id'], 42);
      expect(decoded['nickname'], '瓜呱');
      expect(decoded['verified'], 1);
    });

    test('失败：API 抛异常时不持久化，并向上传播', () async {
      when(
        () => api.login(
          userId: any(named: 'userId'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const ApiException(4001, '账号或密码错误'));

      expect(
        () => repo.login('guagua_001', 'wrong'),
        throwsA(isA<ApiException>()),
      );
      verifyNever(() => storage.write(any(), any()));
    });
  });

  group('AuthRepository.register', () {
    test('成功：返回 AuthEntity 并持久化', () async {
      when(
        () => api.register(
          userId: 'new_user',
          nickname: '新用户',
          password: '123456',
          captchaId: any(named: 'captchaId'),
          captchaText: any(named: 'captchaText'),
          avatar: any(named: 'avatar'),
          bio: any(named: 'bio'),
          location: any(named: 'location'),
        ),
      ).thenAnswer((_) async => _authDto);

      final entity = await repo.register(
        userId: 'new_user',
        nickname: '新用户',
        password: '123456',
        captchaId: 'captcha-id',
        captchaText: 'captcha-text',
      );

      expect(entity.user.id, 42);
      expect(entity.tokens.accessToken, 'access-abc');
      verify(() => storage.write(StorageKeys.accessToken, any())).called(1);
      verify(() => storage.write(StorageKeys.refreshToken, any())).called(1);
      verify(() => storage.write(StorageKeys.userProfile, any())).called(1);
    });

    test('失败：抛异常向上传播且不持久化', () async {
      when(
        () => api.register(
          userId: any(named: 'userId'),
          nickname: any(named: 'nickname'),
          password: any(named: 'password'),
          captchaId: any(named: 'captchaId'),
          captchaText: any(named: 'captchaText'),
          avatar: any(named: 'avatar'),
          bio: any(named: 'bio'),
          location: any(named: 'location'),
        ),
      ).thenThrow(const ApiException(4002, '瓜呱号已存在'));

      expect(
        () => repo.register(
          userId: 'dup',
          nickname: 'n',
          password: '123456',
          captchaId: 'captcha-id',
          captchaText: 'captcha-text',
        ),
        throwsA(isA<ApiException>()),
      );
      verifyNever(() => storage.write(any(), any()));
    });
  });

  group('AuthRepository.logout', () {
    test('成功：调用 api.logout 并清本地', () async {
      when(() => api.logout()).thenAnswer((_) async {});

      await repo.logout();

      verify(() => api.logout()).called(1);
      verify(() => storage.delete(StorageKeys.accessToken)).called(1);
      verify(() => storage.delete(StorageKeys.refreshToken)).called(1);
      verify(() => storage.delete(StorageKeys.userProfile)).called(1);
    });

    test('api.logout 抛异常：仍清本地（finally 保证）', () async {
      when(() => api.logout()).thenThrow(const ApiException(500, '服务器错误'));

      expect(() => repo.logout(), throwsA(isA<ApiException>()));
      try {
        await repo.logout();
      } catch (_) {}

      verify(() => storage.delete(StorageKeys.accessToken)).called(2);
      verify(() => storage.delete(StorageKeys.refreshToken)).called(2);
      verify(() => storage.delete(StorageKeys.userProfile)).called(2);
    });
  });

  group('AuthRepository.restoreSession', () {
    test('无 token：返回 null 且不调 me', () async {
      when(
        () => storage.read(StorageKeys.accessToken),
      ).thenAnswer((_) async => null);

      final result = await repo.restoreSession();

      expect(result, isNull);
      verifyNever(() => api.me());
    });

    test('空 token：返回 null 且不调 me', () async {
      when(
        () => storage.read(StorageKeys.accessToken),
      ).thenAnswer((_) async => '');

      final result = await repo.restoreSession();

      expect(result, isNull);
      verifyNever(() => api.me());
    });

    test('有 token + me 成功：返回 AuthEntity 并刷新本地 user', () async {
      when(
        () => storage.read(StorageKeys.accessToken),
      ).thenAnswer((_) async => 'access-abc');
      when(
        () => storage.read(StorageKeys.refreshToken),
      ).thenAnswer((_) async => 'refresh-xyz');
      when(() => api.me()).thenAnswer((_) async => _userDto);

      final result = await repo.restoreSession();

      expect(result, isNotNull);
      expect(result!.user.id, 42);
      expect(result.user.nickname, '瓜呱');
      expect(result.tokens.accessToken, 'access-abc');
      expect(result.tokens.refreshToken, 'refresh-xyz');
      verify(() => storage.write(StorageKeys.userProfile, any())).called(1);
    });

    test('有 token + me 失败：清本地并返回 null', () async {
      when(
        () => storage.read(StorageKeys.accessToken),
      ).thenAnswer((_) async => 'access-abc');
      when(() => api.me()).thenThrow(const ApiException(401, '未授权'));

      final result = await repo.restoreSession();

      expect(result, isNull);
      verify(() => storage.delete(StorageKeys.accessToken)).called(1);
      verify(() => storage.delete(StorageKeys.refreshToken)).called(1);
      verify(() => storage.delete(StorageKeys.userProfile)).called(1);
    });
  });

  group('AuthRepository.clearLocal', () {
    test('删除 access / refresh / user 三个 key', () async {
      await repo.clearLocal();

      verify(() => storage.delete(StorageKeys.accessToken)).called(1);
      verify(() => storage.delete(StorageKeys.refreshToken)).called(1);
      verify(() => storage.delete(StorageKeys.userProfile)).called(1);
    });
  });

  group('AuthRepository.updateLocalUser', () {
    test('写入 user_profile JSON，含全部字段', () async {
      final user = _userDto.toEntity();

      await repo.updateLocalUser(user);

      final captured = verify(
        () => storage.write(StorageKeys.userProfile, captureAny()),
      ).captured;
      expect(captured.length, 1);
      final json = jsonDecode(captured[0] as String) as Map<String, dynamic>;
      expect(json['id'], 42);
      expect(json['user_id'], 'guagua_001');
      expect(json['nickname'], '瓜呱');
      expect(json['avatar'], 'https://cdn.example.com/a.png');
      expect(json['bio'], '热爱生活');
      expect(json['location'], '上海');
      expect(json['gender'], 1);
      expect(json['follow_count'], 10);
      expect(json['fans_count'], 100);
      expect(json['like_count'], 1000);
      expect(json['post_count'], 5);
      expect(json['verified'], 1);
      expect(json['is_active'], 1);
      expect(json['created_at'], '2026-01-01T00:00:00.000Z');
    });
  });
}
